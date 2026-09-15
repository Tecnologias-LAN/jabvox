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
  # El archivo cargado ahora SOLO aporta destinatario y valores de variables: la
  # plantilla y su idioma se eligen en la UI (como en el flujo de leads). Lo único
  # obligatorio es una columna de número; el nombre y las columnas de variables son
  # opcionales. La columna del número se detecta por cualquiera de estos nombres
  # (case-insensitive), para tolerar archivos que traigan "telefono", "celular", etc.
  NUMBER_HEADERS = %w[numero número telefono teléfono celular movil móvil phone
                      whatsapp msisdn].freeze
  NAME_HEADERS = %w[nombre name].freeze
  MAX_ROWS = 20_000
  CHUNK_SIZE = 200
  MAX_ATTEMPTS = 3
  # El token del envío NO expira por tiempo: un TTL fijo de 30 min caducaba a mitad de los
  # envíos grandes -> 401 "Invalid Access Token". Se revoca cuando el batch termina (lo
  # confirma n8n por callback, ver JabvoxBulkWhatsappBatch#revoke_access_token!).
  # Como RESPALDO, si el callback final nunca llega, un cleanup lo borra tras este tope
  # (dimensionado al volumen para no matar un envío enorme aún en curso).
  BACKUP_CLEANUP_MIN = 6.hours
  BACKUP_CLEANUP_PER_MESSAGE = 3.seconds
  BACKUP_CLEANUP_MAX = 48.hours

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
                 file_name: '', leads_selection: nil, template_name: nil, language: nil, text: nil,
                 variable_map: nil, source_batch_id: nil, number_column: nil, header_media: nil,
                 country: nil, flow_button: nil)
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
    @source_batch_id = source_batch_id
    # Columna del CSV con el número (elegida en la UI). Si es nil, se autodetecta.
    @number_column = number_column.to_s.strip.downcase.presence
    # País del envío por CSV: de él sale el prefijo de los números que llegan sin
    # él. Mismo criterio que la importación de leads — el prefijo NUNCA se adivina
    # a partir del número. Los envíos desde leads no lo usan: su teléfono ya es E.164.
    @country_iso = country.to_s.strip.upcase.presence
    # Media del header de la plantilla ({ media_url, media_type }) — igual para todos.
    @header_media = normalize_header_media(header_media)
    # { "1" => "nombre", "2" => "custom:fecha_entrega2_c", ... } — which lead field
    # fills each {{n}} placeholder of the template body.
    @variable_map = normalize_variable_map(variable_map)
    # Botón FLOW de la plantilla, si tiene uno ({ flow_id }) — igual para todos los
    # destinatarios del envío. Meta exige el componente button/flow SIEMPRE que la
    # plantilla tenga un botón FLOW (no es opcional como un quick reply estático); n8n
    # arma el envío final hacia Meta, así que aquí solo viaja la info necesaria para que
    # pueda construir { type: 'button', sub_type: 'flow', index, parameters: [...] }.
    @flow_button = normalize_flow_button(flow_button)
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
    load_batch_context!(batch)
    messages = expand_messages(batch.payload_jabvox)
    return deliver_nothing(batch) if messages.empty?

    # Persist one recipient row per message BEFORE dispatch so the per-execution
    # report exists immediately and n8n's per-recipient callbacks have a row to
    # update. Idempotent: only seeds when the batch has no recipients yet.
    persist_recipients(batch, messages)

    token = mint_ephemeral_token
    batch.update!(access_token_id_jabvox: token.id) # el batch revoca este token al terminar
    begin
      post_all(batch, messages, token.token)
      # 'queued'/'running' — the real terminal state comes from n8n callbacks.
      finalize(batch, status: 'running', sent_at: Time.current)
    rescue StandardError => e
      token.destroy # never leave a live credential if we couldn't hand it off
      finalize(batch, status: 'failed', error: e.message)
      raise
    end
    schedule_token_cleanup(token, backup_cleanup_for(messages.size))
    batch
  end

  private

  def load_batch_context!(batch)
    @account = batch.account
    @inbox = batch.inbox
    @sender_user = batch.sender_user
    @batch = batch
    ensure_batch_belongs_to_account! # defensa en profundidad multi-tenant
  end

  def deliver_nothing(batch)
    finalize(batch, status: 'failed',
                    error: 'Sin destinatarios válidos: ninguno de los leads seleccionados tiene número de teléfono.')
  end

  # ── Validation ──────────────────────────────────────────────────────────────
  def ensure_configured!
    return if config&.ready?

    raise Error, 'Configura la URL del webhook antes de enviar.'
  end

  def ensure_sender!
    return if @sender_user && @account.users.exists?(id: @sender_user.id)

    raise Error, 'El usuario emisor no es válido para esta cuenta.'
  end

  def ensure_inbox!
    return if @inbox && @account.inboxes.exists?(id: @inbox.id)

    raise Error, 'La bandeja no es válida para esta cuenta.'
  end

  # El inbox y el sender del batch deben pertenecer a la cuenta del batch.
  def ensure_batch_belongs_to_account!
    ensure_inbox!
    ensure_sender!
  end

  # El correo de reporte ya NO es obligatorio: los resultados vuelven a la app por
  # callback de n8n. Solo se valida el formato si el usuario lo proporciona
  # (compatibilidad con quien aún quiera el correo).
  def ensure_email!
    return if @response_email.blank?
    return if @response_email.match?(URI::MailTo::EMAIL_REGEXP)

    raise Error, 'El correo de reporte no tiene un formato válido.'
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
        'template_name' => @template_name, 'language' => @language, 'text' => @text,
        'variable_map' => @variable_map, 'header_media' => @header_media,
        'flow_button' => @flow_button }
    else
      # CSV: la plantilla/idioma vienen de la UI; el archivo solo aporta las filas
      # (número, nombre y columnas de variables). El variable_map mapea {{n}} -> columna.
      { 'kind' => 'csv', 'rows' => parse_rows,
        'template_name' => @template_name, 'language' => @language, 'text' => @text,
        'variable_map' => @variable_map, 'header_media' => @header_media,
        'flow_button' => @flow_button }
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
    source_type = payload['kind'] == 'csv' ? 'csv' : 'jabvox'
    @account.jabvox_bulk_whatsapp_batches.create!(
      inbox: @inbox, sender_user: @sender_user, created_by: @actor,
      response_email_jabvox: @response_email, mode_jabvox: send_mode,
      total_rows_jabvox: total, valid_rows_jabvox: total,
      status_jabvox: 'pending', file_name_jabvox: @file_name, payload_jabvox: payload,
      # Reporting/reuse snapshot (additive columns).
      source_type_jabvox: source_type,
      template_name_jabvox: @template_name, template_language_jabvox: @language,
      variable_mapping_jabvox: @variable_map || {},
      filters_jabvox: (@leads_selection || {})['filters'] || {},
      source_batch_id_jabvox: @source_batch_id
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
    return if NUMBER_HEADERS.intersect?(normalized)

    raise Error, 'El archivo debe tener una columna de número (numero, telefono, celular…).'
  end

  # Longitud mínima de dígitos para aceptar un número (prefijo de país + local).
  # Evita colar celdas basura, pero NO exige un formato exacto: el número debe traer
  # el prefijo de país (p.ej. 57...) — el signo '+' lo antepone el flujo n8n.
  MIN_PHONE_DIGITS = 10

  # El archivo solo aporta destinatario + valores de variables. Se conserva la fila
  # COMPLETA (todas las columnas) en 'cells' para que el variable_map pueda resolver
  # {{n}} contra cualquier columna del CSV. El número debe incluir el prefijo de país;
  # el '+' NO es obligatorio en el archivo (lo maneja n8n). Se descartan celdas vacías
  # o con muy pocos dígitos.
  def normalize_row(row)
    # Todas las columnas de la fila con claves normalizadas (minúsculas, sin espacios),
    # para localizar la columna del número/nombre sin depender de la grafía exacta.
    cells = {}
    row.each do |key, value|
      next if key.nil?

      cells[key.to_s.strip.downcase] = value.to_s.strip
    end

    # Prioriza la columna del número elegida en la UI; si no, autodetecta por sinónimos.
    raw = @number_column ? cells[@number_column] : first_present(cells, NUMBER_HEADERS)
    number = normalize_phone(raw)
    return nil if number.blank?

    name = first_present(cells, NAME_HEADERS)
    { 'nombre' => name.presence || number, 'numero' => number, 'cells' => cells }
  end

  # Primer valor no vacío entre las claves candidatas (ya normalizadas a minúsculas).
  def first_present(cells, keys)
    keys.filter_map { |k| cells[k].presence }.first
  end

  # Normaliza el número del CSV a dígitos listos para la API de WhatsApp.
  #
  # Cuando el envío trae país, el prefijo se aplica con el MISMO servicio que usa
  # la importación de leads: así "3001234567" sale como "573001234567" en vez de
  # irse incompleto y fallar en silencio. Un número que ya trae prefijo no se
  # duplica. Sin país se conserva el comportamiento anterior (solo dígitos), para
  # no cambiar envíos ya configurados.
  def normalize_phone(value)
    return normalize_with_country(value) if @country_iso.present?

    digs = digits(value)
    digs.length >= MIN_PHONE_DIGITS ? digs : nil
  end

  # E.164 sin el '+': es el formato que espera la API de WhatsApp.
  def normalize_with_country(value)
    e164 = Jabvox::LeadIdentityService.normalize_phone(value, @country_iso).value
    return nil if e164.blank?

    e164.delete_prefix('+')
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end

  # ── Phase 2 helpers: expand snapshot -> messages ────────────────────────────
  def expand_messages(payload)
    payload = (payload || {}).with_indifferent_access
    # header_media/flow_button viajan en el snapshot (deliver! reconstruye el service sin ellos).
    @header_media ||= normalize_header_media(payload[:header_media])
    @flow_button ||= normalize_flow_button(payload[:flow_button])
    payload[:kind] == 'leads' ? messages_from_leads(payload) : messages_from_csv(payload)
  end

  # CSV: cada fila -> un mensaje. La plantilla/idioma salen del snapshot (elegidos en
  # la UI, no del archivo); los {{n}} se resuelven mapeando el variable_map contra las
  # columnas de la fila (variable_map = { "1" => "columna_del_csv" }).
  def messages_from_csv(payload)
    body = (payload[:template_name].presence || payload[:text]).to_s.strip
    lang = (payload[:language].presence || 'es')
    var_map = @variable_map.presence || normalize_variable_map(payload[:variable_map])
    return [] if body.blank?

    Array(payload[:rows]).filter_map { |row| csv_message(row, body, lang, var_map) }
  end

  def csv_message(row, body, lang, var_map)
    row = row.with_indifferent_access
    # El número ya viene en E.164 con '+' desde normalize_row; se conserva tal cual.
    number = row[:numero].to_s.strip
    return nil if number.blank?

    cells = (row[:cells] || {}).to_h.transform_keys { |k| k.to_s.strip.downcase }
    {
      'nombre' => row[:nombre].presence || number, 'numero' => number,
      'template' => body, 'idioma' => lang,
      'processed_params' => resolve_params(var_map, cells)
    }
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
    # variable_map may travel in the payload (snapshot) even if it wasn't set on
    # this instance (deliver! rebuilds the service without it).
    var_map = @variable_map.presence || normalize_variable_map(payload[:variable_map])
    scope = @account.jabvox_leads.where(id: ids).includes(:contact, :jabvox_campaign, :jabvox_affiliate, :assignee)

    scope.filter_map do |lead|
      # Número a solo dígitos (con prefijo de país); el '+' lo pone n8n.
      number = normalize_phone(lead.contact&.phone_number)
      next nil if number.blank? || body.to_s.strip.blank?

      lead_message(lead, number, body, lang, var_map)
    end
  end

  # Full lead snapshot per recipient so n8n can personalize, route and report
  # without extra API round-trips. `fields` is the flat name->value map of every
  # default + custom field; `processed_params` are the {{n}} values already
  # resolved from the variable_map, so n8n only forwards them to Meta.
  def lead_message(lead, number, body, lang, var_map = {})
    fields = lead_fields(lead, number)
    {
      'nombre' => fields['nombre'], 'numero' => number,
      'template' => body.to_s.strip, 'idioma' => lang,
      'lead_id' => lead.id, 'lead_number' => lead.lead_number,
      'contact_id' => lead.contact&.id,
      'email' => fields['email'],
      'country' => fields['country'],
      'campaign' => fields['campaign'],
      'assignee_name' => fields['assignee_name'],
      'assignee_email' => fields['assignee_email'],
      'fields' => fields,
      'custom_fields' => lead.custom_fields_jabvox || {},
      'processed_params' => resolve_params(var_map, fields)
    }
  end

  # Flat, string-keyed map of every field usable as a template variable:
  # default lead/contact fields under plain keys, and each custom field under
  # "custom:<key>". This is the single source the variable_map maps against.
  def lead_fields(lead, number)
    contact = lead.contact
    base = {
      'nombre' => contact&.name.to_s,
      'numero' => number,
      'email' => contact&.email.to_s,
      'telefono' => contact&.phone_number.to_s,
      'identificador' => contact&.identifier.to_s,
      'country' => contact&.additional_attributes&.dig('country').to_s,
      'campaign' => lead.jabvox_campaign&.name_jabvox.to_s,
      'afiliado' => lead.jabvox_affiliate&.name.to_s,
      'assignee_name' => lead.assignee&.name.to_s,
      'assignee_email' => lead.assignee&.email.to_s,
      'lead_number' => lead.lead_number.to_s
    }
    (lead.custom_fields_jabvox || {}).each { |k, v| base["custom:#{k}"] = v.to_s }
    base
  end

  # Resolves {{n}} -> value using the variable_map. A mapping value is either a
  # field key present in `fields`, or "text:<literal>" for a fixed value.
  #
  # Devuelve el formato "enhanced" que espera el canal de WhatsApp:
  #   { "body" => { "1" => "Juan", "2" => "..." } }
  # Es OBLIGATORIO anidar bajo "body": el TemplateProcessor de WhatsApp solo trata el
  # mensaje como PLANTILLA si processed_params trae las variables bajo esa clave. Un hash
  # plano { "1" => .. } se ignoraba y el mensaje salía como texto de sesión.
  def resolve_params(var_map, fields)
    body = resolve_body(var_map, fields)
    params = {}
    params['body'] = body if body.present?
    # Header de media de la plantilla ({ media_url, media_type }): igual para todos.
    params['header'] = @header_media if @header_media.present?
    # Botón FLOW: mismo índice/flow_id para todos, pero un flow_token ÚNICO por
    # destinatario (permite correlacionar la respuesta del Flow con este mensaje
    # concreto en el futuro). n8n arma { type: 'button', sub_type: 'flow', index,
    # parameters: [{ type: 'action', action: { flow_token, flow_action_data: {} } }] }.
    params['buttons'] = [flow_button_param] if @flow_button.present?
    params
  end

  def flow_button_param
    {
      'index' => @flow_button['index'],
      'type' => 'flow',
      'flow_id' => @flow_button['flow_id'],
      'flow_token' => SecureRandom.hex(16)
    }
  end

  def resolve_body(var_map, fields)
    return {} if var_map.blank?

    var_map.each_with_object({}) do |(n, source), out|
      out[n.to_s] = if source.to_s.start_with?('text:')
                      source.to_s.sub('text:', '')
                    else
                      fields[source.to_s].to_s
                    end
    end
  end

  # Normaliza el media del header a { 'media_url' =>, 'media_type' => } o nil.
  # media_type debe ser image/video/document (el canal lo exige en minúscula).
  #
  # IMPORTANTE: la URL de EJEMPLO de una plantilla aprobada vive en scontent.whatsapp.net
  # y es firmada/temporal/interna de Meta: NO se puede reenviar como link de media (Meta
  # responde "#100 Invalid parameter"). Para una plantilla con header de media fijo, Meta
  # ya usa la imagen aprobada si NO se envía el componente header. Por eso, cuando la URL
  # es de scontent, devolvemos nil (no se manda header) y el mensaje sale con la media de
  # la plantilla. Solo se reenvía el header si es una URL pública propia y descargable.
  def normalize_header_media(media)
    return nil if media.blank?

    h = (media.respond_to?(:to_unsafe_h) ? media.to_unsafe_h : media).to_h.transform_keys(&:to_s)
    url = h['media_url'].to_s.strip
    type = h['media_type'].to_s.strip.downcase
    return nil if url.blank? || %w[image video document].exclude?(type)
    return nil if meta_sample_media_url?(url)

    { 'media_url' => url, 'media_type' => type }
  end

  # { index: <posición del botón en la plantilla>, flow_id: '...' } — index es el que la
  # UI lee del propio JSON de la plantilla (siempre 0 salvo plantillas con varios botones
  # dinámicos). flow_token se genera por destinatario en el momento del envío real (no
  # aquí), para que cada mensaje tenga uno único que correlacione con la respuesta.
  def normalize_flow_button(button)
    return nil if button.blank?

    h = (button.respond_to?(:to_unsafe_h) ? button.to_unsafe_h : button).to_h.transform_keys(&:to_s)
    { 'index' => h['index'].to_i, 'flow_id' => h['flow_id'].to_s.strip }.tap do |out|
      return nil if out['flow_id'].blank?
    end
  end

  # ¿La URL es el ejemplo interno que Meta guarda en la plantilla aprobada? Esas URLs
  # (scontent.whatsapp.net / lookaside.fbsbx.com) no son reutilizables como link de envío.
  def meta_sample_media_url?(url)
    host = begin
      URI.parse(url).host.to_s.downcase
    rescue URI::InvalidURIError
      ''
    end
    host.end_with?('whatsapp.net') || host.end_with?('fbsbx.com') || host.include?('scontent')
  end

  # Coerces the incoming map to { "<var>" => "fieldkey", ... } with string keys,
  # dropping blanks. La clave es el TOKEN de la variable tal cual: número para
  # plantillas posicionales ({{1}}) o el nombre para plantillas NAMED ({{var1}},
  # {{nombre}}). NO se filtra a solo dígitos (eso rompía las variables con nombre).
  def normalize_variable_map(map)
    return {} if map.blank?

    (map.respond_to?(:to_unsafe_h) ? map.to_unsafe_h : map).to_h.each_with_object({}) do |(k, v), out|
      key = k.to_s.strip
      out[key] = v.to_s if key.present? && v.to_s.present?
    end
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

  # ── Recipients (per-execution report seed) ──────────────────────────────────
  # Seeds one recipient row per outgoing message so the report has a full roster
  # from the start; n8n callbacks then flip each to sent/failed. Idempotent.
  def persist_recipients(batch, messages)
    return if batch.recipients.exists?

    rows = messages.map do |m|
      {
        bulk_whatsapp_batch_id: batch.id,
        account_id: @account.id,
        contact_id: m['contact_id'],
        lead_id_jabvox: m['lead_id']&.to_s,
        name_jabvox: m['nombre'].to_s,
        phone_number_jabvox: m['numero'].to_s,
        email_jabvox: m['email'],
        template_name_jabvox: m['template'].to_s,
        template_language_jabvox: m['idioma'].to_s,
        processed_params_jabvox: m['processed_params'] || {},
        rendered_content_jabvox: render_content(m),
        status_jabvox: 'pending',
        created_at: Time.current, updated_at: Time.current
      }
    end
    JabvoxBulkWhatsappRecipient.insert_all(rows) if rows.any?
    batch.update!(total_recipients_count(batch))
  end

  def total_recipients_count(batch)
    { total_rows_jabvox: batch.recipients.count, valid_rows_jabvox: batch.recipients.count }
  end

  # Best-effort human-readable body for the report (the real send uses
  # processed_params). For templates we don't have the body text here, so we
  # fall back to the template name + resolved params joined.
  def render_content(message)
    params = message['processed_params'] || {}
    body = params['body'] || params[:body] || {}
    return message['template'].to_s if body.blank?

    "#{message['template']} — #{body.values.join(' | ')}"
  end

  # ── Delivery ────────────────────────────────────────────────────────────────
  # POST the messages to n8n in chunks so a 1000+ send never becomes one huge request. Each
  # chunk is retried on transient failures; a chunk that keeps failing aborts the batch.
  def post_all(batch, messages, api_token)
    url = webhook_url
    validate_webhook_url!(url)
    total_chunks = (messages.size.to_f / CHUNK_SIZE).ceil

    messages.each_slice(CHUNK_SIZE).with_index do |chunk, idx|
      meta = { chunk_index: idx, total_chunks: total_chunks }
      post_chunk_with_retries(url, payload_body(batch, chunk, api_token, meta))
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
  def payload_body(batch, messages, api_token, meta)
    {
      base_url: base_url, account_id: @account.id, batch_id: batch.id,
      inbox_id: @inbox&.id, inbox_name: @inbox&.name, mode: send_mode,
      channel_type: @inbox&.channel_type, api_token: api_token,
      # El token ya no expira por tiempo (se revoca al terminar el batch); n8n no debe
      # asumir una caducidad. Se mantiene la clave por compatibilidad del workflow.
      token_expires_at: nil, response_email: @response_email,
      sent_by: @actor&.id, sent_by_name: @actor&.name,
      chunk_index: meta[:chunk_index], total_chunks: meta[:total_chunks], messages: messages
    }.merge(callback_fields(batch))
  end

  # Additive: n8n devuelve el resultado por callback (reemplaza el correo). Se
  # mantiene response_email en el payload por compatibilidad con workflows viejos.
  def callback_fields(batch)
    {
      batch_uuid: batch.batch_uuid_jabvox,
      callback_url: callback_url(batch),
      callback_token: batch.callback_token_jabvox
    }
  end

  # URL del endpoint que n8n llama con los resultados por destinatario y el
  # resumen final. Usa base_url (FRONTEND_URL) + la ruta del batch por uuid.
  def callback_url(batch)
    "#{base_url}/api/v1/accounts/#{@account.id}/jabvox/bulk_whatsapp/batches/#{batch.batch_uuid_jabvox}/results"
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
  # Ventana del cleanup de RESPALDO: cuánto esperar antes de borrar el token si el batch
  # nunca llega a estado terminal (callback final perdido). Proporcional al volumen.
  def backup_cleanup_for(message_count)
    [[BACKUP_CLEANUP_MIN, BACKUP_CLEANUP_PER_MESSAGE * message_count.to_i].max, BACKUP_CLEANUP_MAX].min
  end

  # Token SIN expiración por tiempo: lo revoca el batch al terminar (o el cleanup de
  # respaldo). Así nunca caduca a mitad del envío.
  def mint_ephemeral_token
    AccessToken.create!(owner: @sender_user, expires_at: nil)
  end

  def schedule_token_cleanup(token, wait)
    Jabvox::BulkWhatsappTokenCleanupJob.set(wait: wait + 1.minute).perform_later(token.id)
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
