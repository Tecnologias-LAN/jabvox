require 'csv'
require 'uri'
require 'net/http'

# Prepares and delivers a bulk WhatsApp send in two phases so it scales to 1000+ recipients
# and many concurrent batches without blocking the web request:
#
#   prepare  (in the request)  -> validates, parses the CSV / snapshots the lead selection,
#                                 creates a `pending` JabvoxBulkWhatsappBatch, returns it fast.
#   deliver! (in a background job) -> expands the snapshot into messages, mints a 30-minute
#                                 access token, POSTs to the account's n8n webhook in chunks
#                                 with retries, and marks the batch sent / failed.
#
# The webhook URL runs through the same SSRF host guard as task webhooks. The report email is
# chosen per send and forwarded to n8n so it can email the result there.
class Jabvox::BulkWhatsappDispatchService
  WEBHOOK_PORTS = [80, 443, 8080, 8443].freeze
  REQUIRED_HEADERS = %w[nombre numero template idioma].freeze
  MAX_ROWS = 20_000
  CHUNK_SIZE = 200
  MAX_ATTEMPTS = 3
  TOKEN_TTL = 30.minutes

  class Error < StandardError; end

  # ── Phase 1: build the pending batch (runs in the web request) ──────────────
  #
  #   Jabvox::BulkWhatsappDispatchService.prepare(
  #     account:, inbox:, sender_user:, actor:, response_email:,
  #     csv_io:, file_name:                      # CSV source, OR
  #     leads_selection:, template_name:, language:, text:   # leads source
  #   ) => the persisted pending batch
  def self.prepare(**args)
    new(**args).prepare
  end

  def initialize(account:, inbox:, sender_user:, actor:, response_email: '', csv_io: nil,
                 file_name: '', leads_selection: nil, template_name: nil, language: nil, text: nil)
    @account = account
    @inbox = inbox
    @sender_user = sender_user
    @actor = actor
    @response_email = response_email.to_s.strip
    @csv_io = csv_io
    @file_name = file_name.to_s
    @leads_selection = leads_selection
    @template_name = template_name
    @language = language
    @text = text
  end

  def prepare
    ensure_configured!
    ensure_sender!
    ensure_email!
    payload = build_payload_snapshot
    raise Error, 'No hay destinatarios válidos para enviar.' if payload_empty?(payload)

    batch = create_pending_batch(payload)
    Jabvox::BulkWhatsappDeliverJob.perform_later(batch.id)
    batch
  end

  # ── Phase 2: deliver a queued batch (runs in the background job) ─────────────
  def self.deliver!(batch)
    new(
      account: batch.account, inbox: batch.inbox, sender_user: batch.sender_user,
      actor: batch.created_by, response_email: batch.response_email_jabvox
    ).deliver!(batch)
  end

  def deliver!(batch)
    @account = batch.account
    @inbox = batch.inbox
    @sender_user = batch.sender_user
    messages = expand_messages(batch.payload_jabvox)
    if messages.empty?
      return finalize(batch, status: 'failed',
                      error: 'Sin destinatarios válidos: ninguno de los leads seleccionados tiene número de teléfono.')
    end

    token = mint_ephemeral_token
    begin
      post_all(batch, messages, token.token)
      finalize(batch, status: 'sent', sent_at: Time.current)
    rescue StandardError => e
      token.destroy # never leave a live credential if we couldn't hand it off
      finalize(batch, status: 'failed', error: e.message)
      raise
    end
    schedule_token_cleanup(token)
    batch
  end

  private

  # ── Validation ──────────────────────────────────────────────────────────────
  def ensure_configured!
    return if config&.ready?

    raise Error, 'Configura la URL del webhook antes de enviar.'
  end

  def ensure_sender!
    return if @sender_user && @account.users.exists?(id: @sender_user.id)

    raise Error, 'El usuario emisor no es válido para esta cuenta.'
  end

  def ensure_email!
    return if @response_email.match?(URI::MailTo::EMAIL_REGEXP)

    raise Error, 'Ingresa un correo válido para recibir el reporte.'
  end

  # ── Phase 1 helpers: snapshot what to send ──────────────────────────────────
  # Lead ids are resolved HERE, with the permissions of the user who picked them
  # in the UI (@actor) — so what the picker showed is exactly what gets sent,
  # and an empty selection fails the request immediately instead of the job.
  def build_payload_snapshot
    if @leads_selection
      ids = resolved_lead_ids
      @total_rows = ids.size
      { 'kind' => 'leads', 'lead_ids' => ids, 'selection' => @leads_selection,
        'template_name' => @template_name, 'language' => @language, 'text' => @text }
    else
      { 'kind' => 'csv', 'rows' => parse_rows }
    end
  end

  def resolved_lead_ids
    sel = (@leads_selection || {}).with_indifferent_access
    actor_account_user = @account.account_users.find_by(user_id: @actor.id)
    base = Jabvox::LeadsFilterService.new(
      account: @account, user: @actor,
      is_admin: JabvoxPermissions.user_grants_permission?(actor_account_user, 'jabvox_leads_view_all'),
      filters: sel[:filters] || {}
    ).scope

    scope = if ActiveModel::Type::Boolean.new.cast(sel[:all])
              excluded = Array(sel[:excluded_ids]).map(&:to_i)
              excluded.any? ? base.where.not(jabvox_leads: { id: excluded }) : base
            else
              base.where(jabvox_leads: { id: Array(sel[:lead_ids]).map(&:to_i) })
            end
    scope.limit(MAX_ROWS).pluck(:id)
  end

  def payload_empty?(payload)
    return payload['rows'].blank? if payload['kind'] == 'csv'

    payload['lead_ids'].blank?
  end

  def create_pending_batch(payload)
    # For leads we don't know the exact count until the job resolves it; store what we can.
    total = payload['kind'] == 'csv' ? payload['rows'].size : (@total_rows || 0)
    @account.jabvox_bulk_whatsapp_batches.create!(
      inbox: @inbox, sender_user: @sender_user, created_by: @actor,
      response_email_jabvox: @response_email, mode_jabvox: send_mode,
      total_rows_jabvox: total, valid_rows_jabvox: total,
      status_jabvox: 'pending', file_name_jabvox: @file_name, payload_jabvox: payload
    )
  end

  # ── CSV parsing ─────────────────────────────────────────────────────────────
  def parse_rows
    table = CSV.parse(read_csv, headers: true, skip_blanks: true)
    validate_headers(table.headers)

    rows = table.first(MAX_ROWS)
    @total_rows = rows.size
    rows.filter_map { |row| normalize_row(row) }
  end

  def read_csv
    raw = @csv_io.read.force_encoding('UTF-8')
    raw.valid_encoding? ? raw : raw.encode('UTF-8', invalid: :replace, undef: :replace)
  end

  def validate_headers(headers)
    normalized = Array(headers).compact.map { |h| h.to_s.strip.downcase }
    missing = REQUIRED_HEADERS - normalized
    return if missing.empty?

    raise Error, "Faltan columnas en el CSV: #{missing.join(', ')}. Se requieren: #{REQUIRED_HEADERS.join(', ')}."
  end

  def normalize_row(row)
    number = digits(row['numero'] || row['número'])
    template = row['template'].to_s.strip
    return nil if number.blank? || template.blank?

    { 'nombre' => row['nombre'].to_s.strip, 'numero' => number,
      'template' => template, 'idioma' => (row['idioma'].presence || 'es').to_s.strip }
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end

  # ── Phase 2 helpers: expand snapshot -> messages ────────────────────────────
  def expand_messages(payload)
    payload = (payload || {}).with_indifferent_access
    payload[:kind] == 'leads' ? messages_from_leads(payload) : Array(payload[:rows])
  end

  def messages_from_leads(payload)
    ids = Array(payload[:lead_ids]).map(&:to_i)
    # Batches created before ids were snapshotted still carry only a selection.
    if ids.empty? && payload[:selection].present?
      sel = payload[:selection].with_indifferent_access
      ids = resolve_leads_scope(sel).limit(MAX_ROWS).pluck(:id)
    end

    body = payload[:template_name] || payload[:text]
    lang = (payload[:language].presence || 'es')
    scope = @account.jabvox_leads.where(id: ids).includes(:contact, :jabvox_campaign, :assignee)

    scope.filter_map do |lead|
      number = digits(lead.contact&.phone_number)
      next nil if number.blank? || body.to_s.strip.blank?

      lead_message(lead, number, body, lang)
    end
  end

  # Full lead snapshot per recipient so n8n can personalize, route and report
  # without extra API round-trips.
  def lead_message(lead, number, body, lang)
    contact = lead.contact
    {
      'nombre' => contact&.name.to_s, 'numero' => number,
      'template' => body.to_s.strip, 'idioma' => lang,
      'lead_id' => lead.id, 'lead_number' => lead.lead_number,
      'contact_id' => contact&.id,
      'email' => contact&.email.to_s,
      'country' => contact&.additional_attributes&.dig('country').to_s,
      'campaign' => lead.jabvox_campaign&.name_jabvox.to_s,
      'assignee_name' => lead.assignee&.name.to_s,
      'assignee_email' => lead.assignee&.email.to_s,
      'custom_fields' => lead.custom_fields_jabvox || {}
    }
  end

  def resolve_leads_scope(sel)
    sender_account_user = @account.account_users.find_by(user_id: @sender_user.id)
    base = Jabvox::LeadsFilterService.new(
      account: @account, user: @sender_user,
      is_admin: JabvoxPermissions.user_grants_permission?(sender_account_user, 'jabvox_leads_view_all'),
      filters: sel[:filters] || {}
    ).scope

    if ActiveModel::Type::Boolean.new.cast(sel[:all])
      excluded = Array(sel[:excluded_ids]).map(&:to_i)
      excluded.any? ? base.where.not(jabvox_leads: { id: excluded }) : base
    else
      base.where(jabvox_leads: { id: Array(sel[:lead_ids]).map(&:to_i) })
    end
  end

  # ── Delivery ────────────────────────────────────────────────────────────────
  # POST the messages to n8n in chunks so a 1000+ send never becomes one huge request. Each
  # chunk is retried on transient failures; a chunk that keeps failing aborts the batch.
  def post_all(batch, messages, api_token)
    url = webhook_url
    validate_webhook_url!(url)
    total_chunks = (messages.size.to_f / CHUNK_SIZE).ceil

    messages.each_slice(CHUNK_SIZE).with_index do |chunk, idx|
      post_chunk_with_retries(url, payload_body(batch, chunk, api_token, idx, total_chunks))
    end
    batch.update!(total_rows_jabvox: messages.size, valid_rows_jabvox: messages.size)
  end

  def post_chunk_with_retries(url, body)
    attempt = 0
    begin
      attempt += 1
      response = http_post(url, body)
      return if response.is_a?(Net::HTTPSuccess)

      raise Error, "El webhook respondió #{response.code}."
    rescue StandardError => e
      raise Error, "Fallo al enviar al webhook: #{e.message}" if attempt >= MAX_ATTEMPTS

      sleep(backoff_seconds(attempt))
      retry
    end
  end

  def backoff_seconds(attempt)
    [2**attempt, 8].min
  end

  # base_url lets one n8n workflow serve every account and installation without
  # hardcoding the app host; batch_id ties every chunk back to its send.
  def payload_body(batch, messages, api_token, chunk_index, total_chunks)
    {
      base_url: base_url,
      account_id: @account.id,
      batch_id: batch.id,
      inbox_id: @inbox&.id,
      inbox_name: @inbox&.name,
      mode: send_mode,
      channel_type: @inbox&.channel_type,
      api_token: api_token,
      token_expires_at: TOKEN_TTL.from_now.iso8601,
      response_email: @response_email,
      sent_by: @actor&.id,
      sent_by_name: @actor&.name,
      chunk_index: chunk_index,
      total_chunks: total_chunks,
      messages: messages
    }
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000').to_s.chomp('/')
  end

  def send_mode
    official = @inbox&.channel_type == 'Channel::Whatsapp' ||
               (@inbox&.channel_type == 'Channel::TwilioSms' && @inbox.channel&.medium == 'whatsapp')
    official ? 'template' : 'text'
  end

  def finalize(batch, status:, sent_at: nil, error: nil)
    batch.update!(
      status_jabvox: status, sent_at_jabvox: sent_at,
      error_jabvox: error&.first(500), attempts_jabvox: batch.attempts_jabvox + 1
    )
  end

  # ── Token ───────────────────────────────────────────────────────────────────
  def mint_ephemeral_token
    AccessToken.create!(owner: @sender_user, expires_at: TOKEN_TTL.from_now)
  end

  def schedule_token_cleanup(token)
    Jabvox::BulkWhatsappTokenCleanupJob.set(wait: TOKEN_TTL + 1.minute).perform_later(token.id)
  end

  # ── Webhook plumbing ────────────────────────────────────────────────────────
  def config
    @config ||= @account.jabvox_bulk_whatsapp_config
  end

  def webhook_url
    url = config&.webhook_url_jabvox.to_s.strip
    raise Error, 'No hay URL de webhook configurada para esta cuenta.' if url.blank?

    url
  end

  def validate_webhook_url!(url)
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end
    raise Error, 'La URL del webhook no es válida.' unless uri.is_a?(URI::HTTP) && uri.host.present?

    guard = Jabvox::Analytics::HostGuardService.new(
      host: uri.host, port: uri.port || (uri.scheme == 'https' ? 443 : 80), allowed_ports: WEBHOOK_PORTS
    ).call
    raise Error, "URL de webhook bloqueada: #{guard.reason}" unless guard.allowed?
  end

  def http_post(url, body)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    request.body = body.to_json
    http.request(request)
  end
end
