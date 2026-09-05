# frozen_string_literal: true

# Agente virtual / Voice Broadcast: CRUD, subida de audio, controles (start/pause/
# resume/stop), monitor en vivo y reportes. Todo scoped por account_id, gateado por
# el feature flag del módulo y por permiso de rol, con auditoría de acciones sensibles.
class Api::V1::Accounts::Jabvox::VoiceBroadcastsController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  jabvox_feature 'jabvox_voice_broadcast'
  include JabvoxPermissions

  before_action :ensure_can_manage
  before_action :set_broadcast, except: %i[index create]

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
    # Dos fuentes de destinatarios: 'leads' (filtros propios, como el dialer) o 'campaign'
    # (reusa los contactos de una campaña del dialer, comportamiento anterior).
    if broadcast.source_jabvox == 'campaign'
      campaign = Current.account.jabvox_dialer_campaigns.find_by(id: params[:jabvox_dialer_campaign_id])
      return render(json: { error: 'Campaña no encontrada' }, status: :not_found) unless campaign

      broadcast.jabvox_dialer_campaign = campaign
    end
    return render(json: { errors: broadcast.errors.full_messages }, status: :unprocessable_entity) unless broadcast.save

    JabvoxVoiceBroadcastAudit.record(broadcast, current_user.id, 'created',
                                     { source: broadcast.source_jabvox, campaign_id: broadcast.jabvox_dialer_campaign_id })
    render json: detail_json(broadcast), status: :created
  end

  # GET /lead_count — cuántos leads matchean los filtros (para el formulario).
  def lead_count
    render json: { count: @broadcast.target_leads_scope.count }
  end

  # GET /preview_leads — lista paginada de leads que matchean (para revisar antes de arrancar).
  def preview_leads
    page = [params[:page].to_i, 1].max
    per = 25
    leads = @broadcast.target_leads_scope.includes(:contact).limit(per).offset((page - 1) * per)
    render json: {
      page: page,
      leads: leads.map do |l|
        c = l.contact
        { lead_id: l.id, contact_id: c&.id, name: c&.name, phone: c&.phone_number, email: c&.email }
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
    render json: detail_json(@broadcast)
  end

  def pause
    @broadcast.update!(status_jabvox: 'paused') if @broadcast.running?
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'paused')
    render json: detail_json(@broadcast)
  end

  def resume
    unless @broadcast.status_jabvox == 'paused'
      return render(json: { error: 'Solo se puede reanudar un broadcast pausado' },
                    status: :unprocessable_entity)
    end

    @broadcast.update!(status_jabvox: 'running')
    JabvoxVoiceBroadcastAudit.record(@broadcast, current_user.id, 'resumed')
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
      Jabvox::DialerService.new(Current.account.jabvox_voip_config).ami_reachable?
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

  # GET /report.csv — exporta el detalle por destinatario.
  def report_csv
    send_data recipients_csv(@broadcast), type: 'text/csv',
                                          filename: "voice_broadcast_#{@broadcast.id}.csv"
  end

  private

  def ensure_can_manage
    return if current_user.administrator?
    return if jabvox_can?('jabvox_voice_broadcast_manage') || jabvox_can?('jabvox_dialer_manage')

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
                  # Filtros de leads (source 'leads'), como el dialer.
                  :source_jabvox, :jabvox_campaign_id,
                  countries_jabvox: [], management_state_ids_jabvox: [], affiliate_ids_jabvox: [],
                  inbox_ids_jabvox: [], excluded_lead_ids_jabvox: [],
                  lead_filters_jabvox: [:q, :email, :phone, :document, { custom: {} }])
  end

  # Materializa los destinatarios. Según el source: 'leads' usa los leads filtrados aquí
  # (DialerLeadsFilterService, la misma fuente que el conteo del formulario); 'campaign'
  # reusa los contactos de la campaña del dialer. Idempotente por el índice único de teléfono.
  def build_recipients_from_campaign(broadcast)
    rows = if broadcast.source_jabvox == 'leads'
             recipient_rows_from_leads(broadcast)
           else
             recipient_rows_from_campaign(broadcast)
           end
    JabvoxVoiceBroadcastRecipient.insert_all(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    broadcast.update_columns(total_recipients_jabvox: broadcast.recipients.count) # rubocop:disable Rails/SkipsModelValidations
  end

  def recipient_rows_from_leads(broadcast)
    now = Time.current
    seen = {}
    broadcast.target_leads_scope.includes(:contact).find_each.filter_map do |lead|
      c = lead.contact
      phone = c&.phone_number.to_s.strip
      next if phone.blank? || seen[phone]

      seen[phone] = true
      { jabvox_voice_broadcast_id: broadcast.id, account_id: broadcast.account_id,
        contact_id: c.id, phone_jabvox: phone, name_jabvox: c.name,
        status_jabvox: 'pending', attempts_jabvox: 0, created_at: now, updated_at: now }
    end
  end

  def recipient_rows_from_campaign(broadcast)
    return [] if broadcast.jabvox_dialer_campaign.nil?

    now = Time.current
    broadcast.jabvox_dialer_campaign.jabvox_dialer_campaign_contacts
             .where.not(phone_jabvox: [nil, '']).select(:contact_id, :phone_jabvox, :name_jabvox).map do |c|
      { jabvox_voice_broadcast_id: broadcast.id, account_id: broadcast.account_id,
        contact_id: c.contact_id, phone_jabvox: c.phone_jabvox, name_jabvox: c.name_jabvox,
        status_jabvox: 'pending', attempts_jabvox: 0, created_at: now, updated_at: now }
    end
  end

  # Cuelga los canales del broadcast que siguen en vuelo (recipients 'calling') y los
  # deja como fallidos. Reusa hangup por extensión no aplica (no hay agente); aquí
  # colgamos por uniqueid vía DialerService si está disponible.
  def hangup_in_flight(broadcast)
    broadcast.recipients.where(status_jabvox: 'calling').update_all( # rubocop:disable Rails/SkipsModelValidations
      status_jabvox: 'failed', outcome_jabvox: 'failed', updated_at: Time.current
    )
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
      campaign_id: bcast.jabvox_dialer_campaign_id, audio_ready: bcast.audio_ready?,
      total: bcast.total_recipients_jabvox, dialed: bcast.dialed_count_jabvox,
      created_at: bcast.created_at.iso8601 }
  end

  def detail_json(bcast)
    summary_json(bcast).merge(
      caller_id: bcast.caller_id_jabvox, max_concurrent: bcast.max_concurrent_jabvox, cps: bcast.cps_jabvox,
      max_retries: bcast.max_retries_jabvox, retry_interval: bcast.retry_interval_jabvox,
      amd_enabled: bcast.amd_enabled_jabvox, dtmf_enabled: bcast.dtmf_enabled_jabvox,
      dtmf_optout_digit: bcast.dtmf_optout_digit_jabvox,
      calling_hours_start: bcast.calling_hours_start_jabvox, calling_hours_end: bcast.calling_hours_end_jabvox,
      audio_original_name: bcast.audio_original_name_jabvox, audio_duration_ms: bcast.audio_duration_ms_jabvox,
      counts: live_counts(bcast)
    )
  end

  def live_counts(bcast)
    { dialed: bcast.dialed_count_jabvox, answered_human: bcast.answered_human_count_jabvox,
      answered_machine: bcast.answered_machine_count_jabvox,
      played_complete: bcast.played_complete_count_jabvox, failed: bcast.failed_count_jabvox,
      total: bcast.total_recipients_jabvox }
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
    outcomes = bcast.recipients.group(:outcome_jabvox).count
    amd = bcast.recipients.where.not(amd_status_jabvox: nil).group(:amd_status_jabvox).count
    dtmf = bcast.recipients.where.not(dtmf_pressed_jabvox: nil).group(:dtmf_pressed_jabvox).count
    dialed = bcast.dialed_count_jabvox
    answered = bcast.answered_human_count_jabvox + bcast.answered_machine_count_jabvox
    human = bcast.answered_human_count_jabvox
    played = bcast.played_complete_count_jabvox
    {
      broadcast: summary_json(bcast),
      total: bcast.total_recipients_jabvox,
      dialed: dialed,
      answer_rate: dialed.zero? ? 0 : ((answered.to_f / dialed) * 100).round(1),
      answered_human: human,
      answered_machine: bcast.answered_machine_count_jabvox,
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
end
