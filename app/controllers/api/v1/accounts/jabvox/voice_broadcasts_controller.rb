# frozen_string_literal: true

# Agente virtual / Voice Broadcast: CRUD, subida de audio, controles (start/pause/
# resume/stop), monitor en vivo y reportes. Todo scoped por account_id, gateado por
# el feature flag del módulo y por permiso de rol, con auditoría de acciones sensibles.
class Api::V1::Accounts::Jabvox::VoiceBroadcastsController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  jabvox_feature 'jabvox_voice_broadcast'
  include JabvoxPermissions

  before_action :ensure_can_manage
  # set_broadcast solo aplica a las acciones de MIEMBRO; las de colección (catálogo de
  # leads, historial, analytics) no llevan :id.
  COLLECTION_ACTIONS = %i[index create lead_fields field_values filter_lead_count
                          filter_preview_leads matching_lead_ids history analytics analytics_csv].freeze
  before_action :set_broadcast, except: COLLECTION_ACTIONS

  # Rate-limit de LANZAMIENTOS por cuenta (anti-abuso de marcación automática).
  START_RATELIMIT = 5      # arranques
  START_RATELIMIT_WINDOW = 60 # por minuto

  def index
    broadcasts = JabvoxVoiceBroadcast.for_account(Current.account.id).ordered
    render json: broadcasts.map { |b| summary_json(b) }
  end

  def show
    render json: detail_json(@broadcast)
  end

  def create
    broadcast = JabvoxVoiceBroadcast.new(broadcast_params)
    broadcast.account = Current.account
    broadcast.created_by = current_user
    # Fuente única de destinatarios: los leads de la cuenta filtrados por los criterios
    # propios del módulo (independiente del marcador).
    broadcast.source_jabvox = 'leads'
    return render(json: { errors: broadcast.errors.full_messages }, status: :unprocessable_entity) unless broadcast.save

    JabvoxVoiceBroadcastAudit.record(broadcast, current_user.id, 'created', { source: 'leads' })
    render json: detail_json(broadcast), status: :created
  end

  # ── Catálogo/conteo/preview de leads (colección, sin broadcast guardado) ────
  # Endpoints PROPIOS para el formulario en vivo — no dependen del marcador.

  # GET /lead_fields — definiciones de campos personalizados del lead (para filtrar).
  def lead_fields
    render json: { custom: lead_custom_fields }
  end

  # GET /field_values?key=&q= — valores distintos de un campo custom (autocompletado).
  def field_values
    render json: { values: lead_field_values(params[:key].to_s, params[:q].to_s) }
  end

  # GET /filter_lead_count — cuántos leads matchean el payload de filtros.
  def filter_lead_count
    render json: { count: leads_scope_from_params.count }
  end

  # GET /filter_preview_leads — lista paginada de leads que matchean el payload.
  def filter_preview_leads
    page = [params[:page].to_i, 1].max
    per = 25
    leads = leads_scope_from_params.includes(:contact).limit(per).offset((page - 1) * per)
    render json: {
      page: page, per_page: per, total: leads_scope_from_params.count,
      leads: leads.map { |l| preview_lead_json(l) }
    }
  end

  # GET /matching_lead_ids — todos los ids que matchean (para "deseleccionar todos").
  def matching_lead_ids
    render json: { ids: leads_scope_from_params(with_exclusions: false).pluck(:id) }
  end

  # GET /lead_count — cuántos leads matchean los filtros (para el formulario).
  def lead_count
    render json: { count: @broadcast.target_leads_scope.count }
  end

  # GET /preview_leads — lista paginada de leads que matchean (para revisar antes de arrancar).
  def preview_leads
    page = [params[:page].to_i, 1].max
    per = 25
    # El scope devuelve contactos: se conservan las claves `lead_*` que el frontend ya
    # consume para no romperlo mientras se renombra la pantalla.
    leads = @broadcast.target_leads_scope.limit(per).offset((page - 1) * per)
    render json: {
      page: page,
      leads: leads.map do |c|
        { lead_id: c.id, contact_id: c.id, name: c.name, phone: c.phone_number, email: c.email }
      end
    }
  end

  def update
    return render(json: { error: 'No editable mientras corre' }, status: :unprocessable_entity) if @broadcast.running?
    return render(json: { errors: @broadcast.errors.full_messages }, status: :unprocessable_entity) unless @broadcast.update(broadcast_params)

    render json: detail_json(@broadcast)
  end

  def destroy
    return render(json: { error: 'Detén el broadcast antes de eliminarlo' }, status: :unprocessable_entity) if @broadcast.running?

    # Retención: borra el audio del PBX al eliminar el broadcast.
    Jabvox::VoiceBroadcast::DeployService.new(Current.account).remove(@broadcast.audio_filename_jabvox) if @broadcast.audio_filename_jabvox.present?
    @broadcast.destroy!
    head :no_content
  end

  # POST /audio — sube, valida, transcodifica y despliega el audio al PBX.
  def audio # rubocop:disable Metrics/AbcSize
    file = params[:audio]
    return render(json: { error: 'Adjunta un archivo de audio' }, status: :unprocessable_entity) if file.blank?

    result = Jabvox::VoiceBroadcast::AudioService.new(Current.account).process(file, @broadcast.id)
    return render(json: { error: result.error }, status: :unprocessable_entity) unless result.success

    deployed = Jabvox::VoiceBroadcast::DeployService.new(Current.account).deploy(result.filename)
    @broadcast.update!(
      audio_filename_jabvox: result.filename,
      audio_original_name_jabvox: file.original_filename.to_s[0, 255],
      audio_duration_ms_jabvox: result.duration_ms,
      audio_deployed_jabvox: deployed
    )
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'audio_uploaded', { deployed: deployed })
    render json: { audio_ready: @broadcast.audio_ready?, deployed: deployed, duration_ms: result.duration_ms }
  end

  # POST /start — materializa los destinatarios desde la campaña y arranca la marcación.
  def start
    return render(json: { error: 'Sube y despliega el audio primero' }, status: :unprocessable_entity) unless @broadcast.audio_ready?
    return render(json: { error: 'Límite de arranques alcanzado, intenta en un minuto' }, status: :too_many_requests) unless acquire_start_slot

    build_recipients_from_campaign(@broadcast)
    @broadcast.update!(status_jabvox: 'running', started_at_jabvox: @broadcast.started_at_jabvox || Time.current)
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'started', { total: @broadcast.total_recipients_jabvox })
    # Dispara la marcación INMEDIATAMENTE (no espera al cron del próximo minuto). El job
    # es idempotente (lock por broadcast), así no colisiona con el tick del cron; el cron
    # sigue encargándose de reintentos y de continuar llenando slots.
    Jabvox::VoiceBroadcast::TickAccountJob.perform_later(@broadcast.id)
    render json: detail_json(@broadcast)
  end

  def pause
    @broadcast.update!(status_jabvox: 'paused') if @broadcast.running?
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'paused')
    render json: detail_json(@broadcast)
  end

  # POST /resume — reanuda una campaña pausada y dispara la marcación al instante.
  def resume
    unless @broadcast.status_jabvox == 'paused'
      return render(json: { error: 'Solo se puede reanudar un broadcast pausado' },
                    status: :unprocessable_entity)
    end

    @broadcast.update!(status_jabvox: 'running')
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'resumed')
    Jabvox::VoiceBroadcast::TickAccountJob.perform_later(@broadcast.id) # marca ya, sin esperar al cron
    render json: detail_json(@broadcast)
  end

  # POST /stop — detiene: corta canales en vuelo del broadcast y cierra pendientes.
  def stop
    @broadcast.update!(status_jabvox: 'stopped', finished_at_jabvox: Time.current)
    hangup_in_flight(@broadcast)
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'stopped')
    render json: detail_json(@broadcast)
  end

  # GET /live_monitor — estado en vivo (poll corto).
  def live_monitor
    reachable = begin
      Jabvox::VoiceBroadcast::OriginateService.new(Current.account.jabvox_voip_config).ami_reachable?
    rescue StandardError
      false
    end
    render json: {
      status: @broadcast.status_jabvox,
      in_schedule: @broadcast.in_schedule?,
      pbx_reachable: reachable,
      counts: live_counts(@broadcast),
      remaining: @broadcast.remaining_recipients_count,
      in_flight: @broadcast.in_flight_count,
      server_time: Time.current.iso8601
    }
  end

  # GET /report — reporte histórico detallado.
  def report
    render json: report_json(@broadcast)
  end

  # GET /recipients — detalle por destinatario, paginado y filtrable por estado/desenlace.
  # Sirve para ver "en qué lead va, cuántos llamó, cuáles faltan" en tiempo real.
  def recipients
    page = [params[:page].to_i, 1].max
    per = 50
    scope = @broadcast.recipients.order(updated_at: :desc)
    scope = scope.where(status_jabvox: params[:status]) if params[:status].present?
    scope = scope.where(outcome_jabvox: params[:outcome]) if params[:outcome].present?
    total = scope.count
    rows = scope.limit(per).offset((page - 1) * per)
    render json: {
      page: page, per: per, total: total, total_pages: (total.to_f / per).ceil,
      counts_by_status: @broadcast.recipients.group(:status_jabvox).count,
      recipients: rows.map { |r| recipient_json(r) }
    }
  end

  # GET /call_logs — histórico de CADA llamada individual (una fila por intento), para
  # el reporte completo. Paginado, filtrable por desenlace.
  def call_logs
    page = [params[:page].to_i, 1].max
    per = 50
    scope = @broadcast.call_logs.order(created_at: :desc)
    scope = scope.where(outcome_jabvox: params[:outcome]) if params[:outcome].present?
    total = scope.count
    rows = scope.limit(per).offset((page - 1) * per)
    render json: {
      page: page, per: per, total: total, total_pages: (total.to_f / per).ceil,
      counts_by_outcome: @broadcast.call_logs.group(:outcome_jabvox).count,
      call_logs: rows.map { |l| call_log_json(l) }
    }
  end

  # GET /leads_report — resumen por LEAD/destinatario: cuántas llamadas, estado final,
  # cuánto tardó en contestar, cuánto escuchó el audio, duración total. Lista del reporte
  # "por lead".
  def leads_report
    rows = @broadcast.recipients.includes(:call_logs).map do |r|
      logs = r.call_logs.to_a
      answered = logs.select { |l| %w[answered_human answered_machine].include?(l.outcome_jabvox) }.max_by(&:attempt_number_jabvox)
      {
        recipient_id: r.id, phone: r.phone_jabvox, name: r.name_jabvox,
        status: r.status_jabvox, final_outcome: r.outcome_jabvox,
        total_calls: logs.size, attempts: r.attempts_jabvox,
        answered: answered.present?,
        ring_ms: (answered&.ring_ms_jabvox || r.ring_ms_jabvox), # tardó en contestar
        listened_ms: (answered&.duration_ms_jabvox || r.duration_ms_jabvox), # escuchó del audio
        played_full: logs.any?(&:played_full_jabvox) || r.played_full_jabvox,
        total_duration_ms: logs.filter_map(&:total_duration_ms_jabvox).max,
        last_call_at: (logs.filter_map(&:ended_at_jabvox).max || r.last_attempt_at_jabvox)&.iso8601
      }
    end
    render json: { total: rows.size, leads: rows }
  end

  # GET /report.csv — exporta el detalle por destinatario.
  def report_csv
    send_data recipients_csv(@broadcast), type: 'text/csv',
                                          filename: "voice_broadcast_#{@broadcast.id}.csv"
  end

  # ── Historial y reportes globales (cross-campaña) ───────────────────────────

  # GET /history — historial de envíos: qué campaña, cuándo, cuántos, y cómo fue
  # (contestó/reprodujo/falló). Paginado, filtrable por estado y rango de fechas.
  def history
    page = [params[:page].to_i, 1].max
    per = params[:per].blank? ? 20 : params[:per].to_i.clamp(1, 100)
    scope = history_scope
    total = scope.count
    rows = scope.order(created_at: :desc).limit(per).offset((page - 1) * per)
    render json: {
      page: page, per: per, total: total, total_pages: (total.to_f / per).ceil,
      items: rows.map { |b| history_json(b) }
    }
  end

  # GET /analytics — métricas agregadas de TODAS las campañas en un rango de fechas:
  # cuántas llamadas, contestó humano/máquina, reprodujo el audio completo, no contestó,
  # falló, tasa de contestación, y desglose por desenlace/AMD/DTMF.
  def analytics
    scope = history_scope
    render json: analytics_json(scope)
  end

  # GET /analytics.csv — exporta el resumen por campaña del rango.
  def analytics_csv
    send_data analytics_csv_data(history_scope), type: 'text/csv',
                                                 filename: "voice_broadcast_analytics_#{Date.current}.csv"
  end

  private

  def ensure_can_manage
    return if current_user.administrator?
    # Permiso PROPIO del módulo (no depende del marcador).
    return if jabvox_can?('jabvox_voice_broadcast_manage')

    render json: { error: 'No tienes permiso para gestionar el agente virtual' }, status: :forbidden
  end

  def set_broadcast
    @broadcast = JabvoxVoiceBroadcast.for_account(Current.account.id).find_by(id: params[:id])
    render(json: { error: 'Broadcast no encontrado' }, status: :not_found) unless @broadcast
  end

  def broadcast_params
    params.permit(:name_jabvox, :caller_id_jabvox, :max_concurrent_jabvox, :cps_jabvox,
                  :max_retries_jabvox, :retry_interval_jabvox, :amd_enabled_jabvox,
                  :dtmf_enabled_jabvox, :dtmf_optout_digit_jabvox,
                  :calling_hours_start_jabvox, :calling_hours_end_jabvox,
                  # Filtros de leads propios del módulo (independientes del marcador).
                  countries_jabvox: [], management_state_ids_jabvox: [], affiliate_ids_jabvox: [],
                  inbox_ids_jabvox: [], excluded_lead_ids_jabvox: [],
                  lead_filters_jabvox: [:q, :email, :phone, :document, { custom: {} }])
  end

  # Materializa los destinatarios desde los leads filtrados por los criterios propios del
  # módulo (LeadsFilterService del VB, la misma fuente que el conteo del formulario).
  # Al RE-arrancar una campaña ya materializada, reabre los destinatarios ya cerrados a
  # 'pending' (para volver a marcarlos) e inserta los nuevos que matcheen. Usa unique_by
  # para NO lanzar 500 ante el índice único (broadcast_id, phone).
  def build_recipients_from_campaign(broadcast)
    # Re-arranque: reabre los destinatarios previos (done/failed) a pending, limpio.
    broadcast.recipients.where.not(status_jabvox: 'pending').update_all( # rubocop:disable Rails/SkipsModelValidations
      status_jabvox: 'pending', outcome_jabvox: nil, attempts_jabvox: 0, uniqueid_jabvox: nil,
      linkedid_jabvox: nil, amd_status_jabvox: nil, dtmf_pressed_jabvox: nil, played_full_jabvox: false,
      duration_ms_jabvox: nil, answered_at_jabvox: nil, ring_ms_jabvox: nil, last_attempt_at_jabvox: nil,
      updated_at: Time.current
    )
    now = Time.current
    seen = {}
    rows = broadcast.target_leads_scope.includes(:contact).find_each.filter_map do |lead|
      c = lead.contact
      phone = c&.phone_number.to_s.strip
      next if phone.blank? || seen[phone]

      seen[phone] = true
      { jabvox_voice_broadcast_id: broadcast.id, account_id: broadcast.account_id,
        contact_id: c.id, phone_jabvox: phone, name_jabvox: c.name,
        status_jabvox: 'pending', attempts_jabvox: 0, created_at: now, updated_at: now }
    end
    # unique_by evita el 500 si un teléfono ya existe en el broadcast (idempotente).
    JabvoxVoiceBroadcastRecipient.insert_all(rows, unique_by: %i[jabvox_voice_broadcast_id phone_jabvox]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    broadcast.update_columns(total_recipients_jabvox: broadcast.recipients.count) # rubocop:disable Rails/SkipsModelValidations
  end

  # ── Filtros de leads (colección): construye el scope desde el payload ────────
  def filter_params_hash(with_exclusions: true) # rubocop:disable Metrics/AbcSize
    custom = params[:custom].respond_to?(:to_unsafe_h) ? params[:custom].to_unsafe_h : (params[:custom] || {})
    hash = {
      countries: Array(params[:countries]),
      management_state_ids: Array(params[:management_state_ids]).map(&:to_s),
      affiliate_ids: Array(params[:affiliate_ids]),
      inbox_ids: Array(params[:inbox_ids]),
      q: params[:q], email: params[:email], phone: params[:phone], document: params[:document],
      custom: custom, require_phone: true
    }
    hash[:excluded_lead_ids] = Array(params[:excluded_lead_ids]) if with_exclusions
    hash
  end

  def leads_scope_from_params(with_exclusions: true)
    Jabvox::VoiceBroadcast::ContactsFilterService.new(Current.account, filter_params_hash(with_exclusions: with_exclusions)).scope
  end

  def preview_lead_json(lead)
    c = lead.contact
    { lead_id: lead.id, contact_id: c&.id, name: c&.name, phone: c&.phone_number, email: c&.email }
  end

  # Campos personalizados del lead: definiciones de la tabla custom de leads MÁS las
  # claves descubiertas en los datos (variantes _c), para que todo campo sea filtrable.
  # Usa Jabvox::LeadCustomFilter (clase NEUTRAL compartida, no del marcador).
  def lead_custom_fields # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    table = Current.account.jabvox_custom_tables.for_contacts.first
    columns = table ? table.jabvox_custom_columns.ordered : []
    defined_keys = columns.map(&:name_jabvox)
    defined_expanded = defined_keys.flat_map { |k| Jabvox::LeadCustomFilter.key_variants(k) }
    extra_keys = Jabvox::LeadCustomFilter.data_keys(Current.account) - defined_expanded
    values_by_key = Jabvox::LeadCustomFilter.distinct_values(Current.account, defined_keys + extra_keys)

    defined = columns.map do |c|
      custom_field_json(c.name_jabvox, c.label_jabvox, c.column_type_jabvox,
                        Array(c.options_jabvox).map(&:to_s), values_by_key)
    end
    discovered = extra_keys.map { |key| custom_field_json(key, key.tr('_', ' ').capitalize, 'text', [], values_by_key) }
    defined + discovered
  rescue StandardError
    []
  end

  def custom_field_json(key, label, column_type, configured, values_by_key)
    discovered = values_by_key[key] || []
    { key: key, label: label, column_type: column_type,
      options: (configured + discovered).reject(&:blank?).uniq.sort, truncated: discovered.size >= 200 }
  end

  # Valores distintos de un campo custom (búsqueda server-side para campos truncados).
  def lead_field_values(key, query)
    return [] if key.blank?

    Jabvox::LeadCustomFilter.distinct_values_search(Current.account, key, query, limit: 50)
  rescue StandardError
    []
  end

  # Cuelga de verdad los canales del broadcast que siguen en vuelo (recipients 'calling'):
  # emite un Hangup AMI por su uniqueid para que dejen de sonar/reproducir en el PBX, y
  # los cierra en BD como fallidos, incrementando el contador de fallidos de forma
  # consistente. Sin esto, "detener" solo cambiaba la BD y las llamadas seguían activas.
  def hangup_in_flight(broadcast)
    in_flight = broadcast.recipients.where(status_jabvox: 'calling').to_a
    return if in_flight.empty?

    svc = begin
      Jabvox::VoiceBroadcast::OriginateService.new(Current.account.jabvox_voip_config)
    rescue StandardError
      nil
    end
    in_flight.each { |r| svc&.hangup(r.uniqueid_jabvox) if r.uniqueid_jabvox.present? }
    broadcast.recipients.where(status_jabvox: 'calling').update_all( # rubocop:disable Rails/SkipsModelValidations
      status_jabvox: 'failed', outcome_jabvox: 'failed', updated_at: Time.current
    )
    JabvoxVoiceBroadcast.where(id: broadcast.id)
                        .update_all("failed_count_jabvox = failed_count_jabvox + #{in_flight.size}") # rubocop:disable Rails/SkipsModelValidations
  end

  def acquire_start_slot
    key = "jabvox_vb_start_#{Current.account.id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, START_RATELIMIT_WINDOW) if count == 1
    count <= START_RATELIMIT
  rescue StandardError
    true # si Redis falla, no bloqueamos (el arranque no es abusable sin Redis roto)
  end

  # ── serializers ──────────────────────────────────────────────────────────

  def summary_json(bcast)
    { id: bcast.id, name: bcast.name_jabvox, status: bcast.status_jabvox,
      audio_ready: bcast.audio_ready?,
      total: bcast.total_recipients_jabvox, dialed: bcast.dialed_count_jabvox,
      answered_human: bcast.answered_human_count_jabvox,
      created_at: bcast.created_at.iso8601 }
  end

  def detail_json(bcast) # rubocop:disable Metrics/CyclomaticComplexity
    summary_json(bcast).merge(
      source: bcast.source_jabvox,
      caller_id: bcast.caller_id_jabvox, max_concurrent: bcast.max_concurrent_jabvox, cps: bcast.cps_jabvox,
      max_retries: bcast.max_retries_jabvox, retry_interval: bcast.retry_interval_jabvox,
      amd_enabled: bcast.amd_enabled_jabvox, dtmf_enabled: bcast.dtmf_enabled_jabvox,
      dtmf_optout_digit: bcast.dtmf_optout_digit_jabvox,
      calling_hours_start: bcast.calling_hours_start_jabvox, calling_hours_end: bcast.calling_hours_end_jabvox,
      audio_original_name: bcast.audio_original_name_jabvox, audio_duration_ms: bcast.audio_duration_ms_jabvox,
      # Filtros de leads (para reconstruir el formulario al editar).
      countries: bcast.countries_jabvox || [],
      management_state_ids: (bcast.management_state_ids_jabvox || []).map(&:to_s),
      affiliate_ids: bcast.affiliate_ids_jabvox || [],
      inbox_ids: bcast.inbox_ids_jabvox || [],
      excluded_lead_ids: bcast.excluded_lead_ids_jabvox || [],
      lead_filters: (bcast.lead_filters_jabvox || {}).slice('q', 'email', 'phone', 'document', 'custom'),
      counts: live_counts(bcast)
    )
  end

  def live_counts(bcast)
    { dialed: bcast.dialed_count_jabvox, answered_human: bcast.answered_human_count_jabvox,
      answered_machine: bcast.answered_machine_count_jabvox,
      played_complete: bcast.played_complete_count_jabvox, failed: bcast.failed_count_jabvox,
      total: bcast.total_recipients_jabvox }
  end

  # Vista por LLAMADA individual (histórico completo) para el reporte.
  #   ring_ms          = cuánto tardó en contestar (timbrado).
  #   duration_ms      = tiempo de conversación / audio escuchado (billsec).
  #   total_duration_ms= duración total de la llamada (ring + conversación).
  #   played_full      = escuchó el audio completo (true/false).
  def call_log_json(log)
    { id: log.id, phone: log.phone_jabvox, name: log.name_jabvox,
      attempt: log.attempt_number_jabvox, outcome: log.outcome_jabvox,
      amd: log.amd_status_jabvox, dtmf: log.dtmf_pressed_jabvox,
      played_full: log.played_full_jabvox,
      ring_ms: log.ring_ms_jabvox,
      duration_ms: log.duration_ms_jabvox,
      total_duration_ms: log.total_duration_ms_jabvox,
      recording: log.recording_file_jabvox, hangup_cause: log.hangup_cause_jabvox,
      answered_at: log.answered_at_jabvox&.iso8601,
      started_at: log.started_at_jabvox&.iso8601, ended_at: log.ended_at_jabvox&.iso8601 }
  end

  # Vista por destinatario para la tabla de detalle/monitor.
  def recipient_json(r)
    { id: r.id, phone: r.phone_jabvox, name: r.name_jabvox, status: r.status_jabvox,
      outcome: r.outcome_jabvox, amd: r.amd_status_jabvox, dtmf: r.dtmf_pressed_jabvox,
      played_full: r.played_full_jabvox, attempts: r.attempts_jabvox,
      duration_ms: r.duration_ms_jabvox, recording: r.recording_file_jabvox,
      last_attempt_at: r.last_attempt_at_jabvox&.iso8601 }
  end

  def report_json(bcast) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # Los desgloses vienen del HISTÓRICO de llamadas (call_logs) para reflejar TODAS las
    # llamadas hechas (incluidos los reintentos), no solo el último estado del destinatario.
    logs = bcast.call_logs
    outcomes = logs.where.not(outcome_jabvox: nil).group(:outcome_jabvox).count
    amd = logs.where.not(amd_status_jabvox: nil).group(:amd_status_jabvox).count
    dtmf = logs.where.not(dtmf_pressed_jabvox: nil).group(:dtmf_pressed_jabvox).count
    total_calls = logs.count
    # human/machine para las TASAS: destinatarios distintos con ese desenlace final
    # (no llamadas), consistente con history_json y analytics_json.
    human = bcast.recipients.where(outcome_jabvox: 'answered_human').count
    machine = bcast.recipients.where(outcome_jabvox: 'answered_machine').count
    played = bcast.recipients.where(played_full_jabvox: true).count
    dialed = bcast.recipients.where.not(status_jabvox: 'pending').count
    {
      broadcast: summary_json(bcast),
      total: bcast.total_recipients_jabvox,
      dialed: dialed, # destinatarios distintos marcados (no intentos)
      total_calls: total_calls, # nº total de llamadas hechas (con reintentos)
      answer_rate: dialed.zero? ? 0 : (((human + machine).to_f / dialed) * 100).round(1),
      answered_human: human,
      answered_machine: machine,
      played_complete: played,
      played_complete_rate: human.zero? ? 0 : ((played.to_f / human) * 100).round(1),
      outcomes: outcomes,
      amd_breakdown: amd,
      dtmf_breakdown: dtmf,
      started_at: bcast.started_at_jabvox&.iso8601,
      finished_at: bcast.finished_at_jabvox&.iso8601
    }
  end

  def recipients_csv(bcast)
    require 'csv'
    CSV.generate do |csv|
      csv << ['Telefono', 'Nombre', 'Estado', 'Desenlace', 'AMD', 'Escucho completo',
              'DTMF', 'Intentos', 'Duracion(ms)', 'Grabacion', 'Ultima marcacion']
      bcast.recipients.order(:id).find_each do |r|
        csv << [r.phone_jabvox, r.name_jabvox, r.status_jabvox, r.outcome_jabvox,
                r.amd_status_jabvox, r.played_full_jabvox, r.dtmf_pressed_jabvox,
                r.attempts_jabvox, r.duration_ms_jabvox, r.recording_file_jabvox,
                r.last_attempt_at_jabvox&.iso8601]
      end
    end
  end

  # ── Historial / analytics helpers ───────────────────────────────────────────

  # Scope de campañas del historial, con filtros opcionales de estado y rango de fechas.
  def history_scope # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    scope = JabvoxVoiceBroadcast.for_account(Current.account.id)
    scope = scope.where(status_jabvox: params[:status]) if params[:status].present?
    if params[:from].present?
      from = begin
        Time.zone.parse(params[:from].to_s)
      rescue StandardError
        nil
      end
      scope = scope.where('created_at >= ?', from.beginning_of_day) if from
    end
    if params[:to].present?
      to = begin
        Time.zone.parse(params[:to].to_s)
      rescue StandardError
        nil
      end
      scope = scope.where('created_at <= ?', to.end_of_day) if to
    end
    scope
  end

  # Una fila de historial: qué campaña, cuándo, cuántos y cómo resultó el envío.
  # "dialed" = destinatarios DISTINTOS que salieron de pending (no intentos), y la tasa
  # se calcula sobre ese denominador, para que cuadre con analytics y el report.
  def history_json(bcast)
    recipients = bcast.recipients
    dialed = recipients.where.not(status_jabvox: 'pending').count
    human = recipients.where(outcome_jabvox: 'answered_human').count
    machine = recipients.where(outcome_jabvox: 'answered_machine').count
    {
      id: bcast.id, name: bcast.name_jabvox, status: bcast.status_jabvox,
      total: bcast.total_recipients_jabvox, dialed: dialed,
      total_calls: bcast.call_logs.count, # nº total de llamadas (con reintentos)
      answered_human: human, answered_machine: machine,
      played_complete: recipients.where(played_full_jabvox: true).count,
      failed: recipients.where(status_jabvox: 'failed').count,
      answer_rate: dialed.zero? ? 0 : (((human + machine).to_f / dialed) * 100).round(1),
      created_at: bcast.created_at.iso8601,
      started_at: bcast.started_at_jabvox&.iso8601,
      finished_at: bcast.finished_at_jabvox&.iso8601
    }
  end

  # Agregado cross-campaña para la pestaña de reportes.
  def analytics_json(scope) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    ids = scope.pluck(:id)
    recipients = JabvoxVoiceBroadcastRecipient.where(jabvox_voice_broadcast_id: ids)
    dialed = recipients.where.not(status_jabvox: 'pending').count
    human = recipients.where(outcome_jabvox: 'answered_human').count
    machine = recipients.where(outcome_jabvox: 'answered_machine').count
    played = recipients.where(played_full_jabvox: true).count
    failed = recipients.where(status_jabvox: 'failed').count
    {
      campaigns: scope.count,
      total_recipients: recipients.count,
      dialed: dialed,
      answered_human: human,
      answered_machine: machine,
      played_complete: played,
      no_answer: recipients.where(outcome_jabvox: %w[no_answer busy congestion]).count,
      failed: failed,
      answer_rate: dialed.zero? ? 0 : (((human + machine).to_f / dialed) * 100).round(1),
      played_rate: human.zero? ? 0 : ((played.to_f / human) * 100).round(1),
      outcomes: recipients.where.not(outcome_jabvox: nil).group(:outcome_jabvox).count,
      amd_breakdown: recipients.where.not(amd_status_jabvox: nil).group(:amd_status_jabvox).count,
      by_campaign: scope.order(created_at: :desc).limit(200).map { |b| history_json(b) }
    }
  end

  def analytics_csv_data(scope)
    require 'csv'
    CSV.generate do |csv|
      csv << ['Campana', 'Estado', 'Total', 'Marcados', 'Contesto humano', 'Contesto maquina',
              'Reprodujo completo', 'Fallidos', 'Tasa contestacion (%)', 'Creada', 'Finalizada']
      scope.order(created_at: :desc).find_each do |b|
        h = history_json(b)
        csv << [h[:name], h[:status], h[:total], h[:dialed], h[:answered_human], h[:answered_machine],
                h[:played_complete], h[:failed], h[:answer_rate], h[:created_at], h[:finished_at]]
      end
    end
  end
end
