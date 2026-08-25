# frozen_string_literal: true

# Sync bidireccional de modelos entre el ai-chat de la cuenta y su Hermes: PUSH de los
# locales a Hermes, PULL de los de Hermes al ai-chat (source='hermes'). Requiere handoff
# operativo y Hermes vivo. Habla con el Hermes de la cuenta vía Jabvox::Hermes::Client.
class Jabvox::Hermes::ModelSyncService
  Result = Struct.new(:success, :pushed, :pulled, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(account, client: Jabvox::Hermes::Client.new)
    @account = account
    @client = client
    @handoff = account.jabvox_context_forge_handoff
  end

  def call
    return failure('La cuenta no está aprovisionada.') if @handoff.nil? || !@handoff.ready_for_chat?
    return failure('Hermes no está configurado (falta URL).') if hermes_base_url.blank?

    remote = fetch_remote_models
    return failure(remote.error) unless remote.success?

    pulled = import_remote_models(remote.data)
    pushed = export_local_models
    Result.new(success: true, pushed: pushed, pulled: pulled)
  rescue StandardError => e
    Rails.logger.error("[ModelSync] account=#{@account.id} error=#{e.class}")
    failure(e.message)
  end

  private

  # URL del Hermes de ESTA cuenta (del handoff); si no, la global.
  def hermes_base_url
    @handoff&.hermes_url.presence || Jabvox::Hermes::Client.hermes_url
  end

  # GET modelos que ofrece el Hermes de la cuenta (OpenAI-compat: /v1/models).
  def fetch_remote_models
    conn = hermes_conn
    resp = conn.get('v1/models')
    if resp.success?
      list = resp.body.is_a?(Hash) ? (resp.body['data'] || []) : Array(resp.body)
      Jabvox::Hermes::Client::Result.new(success: true, data: list)
    else
      Jabvox::Hermes::Client::Result.new(success: false, error: "Hermes respondió #{resp.status}")
    end
  rescue Faraday::Error => e
    Jabvox::Hermes::Client::Result.new(success: false, error: "No se pudo listar modelos de Hermes: #{e.class}")
  end

  # PULL: crea/actualiza en el ai-chat los modelos de Hermes no presentes localmente.
  def import_remote_models(remote_list)
    count = 0
    remote_list.each do |m|
      mid = m.is_a?(Hash) ? (m['id'] || m['model']) : m.to_s
      next if mid.blank?
      next if @account.jabvox_ai_chat_models.exists?(hermes_model_id_jabvox: mid)
      next if @account.jabvox_ai_chat_models.exists?(model_jabvox: mid, source_jabvox: 'local')

      @account.jabvox_ai_chat_models.create!(
        name_jabvox: "Hermes · #{mid}".first(150),
        provider_jabvox: 'custom',
        model_jabvox: mid.first(200),
        base_url_jabvox: hermes_base_url.first(500),
        # AISLAMIENTO: el api_key de un modelo Hermes ES el scoped token de ESTA cuenta.
        # El gateway Hermes lo valida contra el Hermes de la cuenta; con él, el ai-chat solo
        # puede tocar las MCPs de su propia cuenta (403 en cualquier otra).
        api_key_jabvox: @handoff.scoped_token,
        source_jabvox: 'hermes',
        hermes_model_id_jabvox: mid,
        is_default_jabvox: false
      )
      count += 1
    end
    count
  end

  # PUSH: informa a Hermes de los modelos locales (para que /model pueda fijarlos).
  # Best-effort: si el endpoint no existe en Hermes, no rompe el sync (el PULL es lo crítico).
  def export_local_models
    locals = @account.jabvox_ai_chat_models.where(source_jabvox: 'local')
    payload = locals.map { |m| { id: m.model_jabvox, name: m.name_jabvox, base_url: m.base_url_jabvox } }
    resp = hermes_conn.post('jabvox/models') { |r| r.body = { models: payload } }
    resp.success? ? locals.size : 0
  rescue Faraday::Error
    0 # push best-effort; no bloquea el pull
  end

  def hermes_conn
    base = hermes_base_url
    normalized = base.end_with?('/') ? base : "#{base}/"
    Faraday.new(url: normalized) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.options.open_timeout = 5
      f.options.timeout = 20
      f.headers['Authorization'] = "Bearer #{@handoff.scoped_token}"
      f.adapter Faraday.default_adapter
    end
  end

  def failure(msg)
    Result.new(success: false, error: msg, pushed: 0, pulled: 0)
  end
end
