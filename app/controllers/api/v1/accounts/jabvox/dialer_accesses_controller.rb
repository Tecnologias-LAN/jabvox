# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::DialerAccessesController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  jabvox_feature 'jabvox_dialer'
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :require_admin, except: %i[me connect disconnect update_state heartbeat request_call end_call]

  AGENT_TTL = 10.minutes.to_i

  def index
    accesses = Current.account.jabvox_dialer_accesses
    render json: accesses.map { |a| { id: a.id, user_id: a.user_id, can_access: a.can_access } }
  end

  def update
    access = Current.account.jabvox_dialer_accesses.find_or_initialize_by(user_id: params[:id])
    access.update!(can_access: params[:can_access])
    render json: { id: access.id, user_id: access.user_id, can_access: access.can_access }
  end

  def me
    can_access = Current.account.jabvox_dialer_accesses.exists?(user_id: current_user.id, can_access: true)
    render json: { can_access: can_access }
  end

  def connect
    user_ext = Current.account.jabvox_user_extensions.find_by(user_id: current_user.id)
    campaign_id = params[:campaign_id]&.to_i

    # An agent may only connect to a campaign inside its management window.
    if campaign_id&.positive?
      campaign = Current.account.jabvox_dialer_campaigns.find_by(id: campaign_id)
      if campaign && !campaign.in_schedule?
        return render json: { error: 'Campaign out of schedule', out_of_schedule: true },
                      status: :unprocessable_entity
      end
    end
    agent_data = {
      user_id: current_user.id,
      campaign_id: campaign_id,
      extension: user_ext&.extension_jabvox,
      state_id: nil,
      connected_at: Time.current.to_i,
      # Cuándo cambió por última vez el estado visible (esperando/pausa/llamada),
      # para el "tiempo en estado" del reporte de agentes.
      state_changed_at: Time.current.to_i,
      pubsub_token: current_user.pubsub_token
    }
    write_agent_state(agent_data)
    register_connected_agent(current_user.id)
    sync_queue_membership(campaign_id, user_ext&.extension_jabvox, add: true)
    record_agent_state('waiting')
    log_connect(Current.account.id, current_user.id, user_ext&.extension_jabvox, campaign_id)
    render json: { extension: user_ext&.extension_jabvox }
  end

  def disconnect
    data = read_agent_state
    sync_queue_membership(data&.dig(:campaign_id), data&.dig(:extension), add: false) if data
    remove_agent_state
    unregister_connected_agent(current_user.id)
    record_agent_state('inactive')
    head :no_content
  end

  def update_state
    data = read_agent_state
    return head :not_found unless data

    paused = params[:state_id].present?
    new_state_id = params[:state_id].presence&.to_i
    data[:state_changed_at] = Time.current.to_i if data[:state_id] != new_state_id
    data[:state_id] = new_state_id
    write_agent_state(data)
    sync_queue_pause(data[:campaign_id], data[:extension], paused: paused)
    # Pausa => paused; despausa sin llamada => waiting (si está en llamada, el
    # listener ya lo marcó in_call y no lo pisamos aquí).
    record_agent_state(next_state_after_update(paused, data))
    head :ok
  end

  def next_state_after_update(paused, data)
    return 'paused' if paused

    data[:in_call_contact_id].present? ? 'in_call' : 'waiting'
  end

  def heartbeat
    data = read_agent_state
    # 404 explícito cuando la sesión Redis expiró/no existe: el frontend lo usa
    # para reconciliar (reconectar o soltar una llamada fantasma) en vez de
    # seguir mostrando al agente "en llamada" indefinidamente.
    return render json: { connected: false }, status: :not_found unless data

    # Renovar SOLO el TTL de forma atómica (EXPIRE), sin reescribir el blob.
    # Reescribirlo con la copia leída pisaba el in_call_contact_id que el AMI
    # listener podía haber añadido entre el read y el write (race entre Puma y
    # el runner AMI): el agente aparecía "esperando" estando en llamada.
    touch_agent_state
    # Releer para reflejar el in_call que el listener haya escrito mientras tanto.
    fresh = read_agent_state || data
    render json: { connected: true, in_call: fresh[:in_call_contact_id].present?,
                   in_call_contact_id: fresh[:in_call_contact_id], state_id: fresh[:state_id] }
  end

  def available_agents
    trunk = Current.account.jabvox_voip_config&.dialer_trunk.presence
    ids = connected_agent_ids
    agents = ids.filter_map do |uid|
      state = read_agent_state_for(uid)
      next unless state && state[:state_id].nil?

      { user_id: state[:user_id], extension: state[:extension],
        campaign_id: state[:campaign_id], dialer_trunk: trunk }
    end
    render json: agents
  end

  # Lock por agente: evita que dos peticiones solapadas del mismo agente
  # (polling con PBX lento, o dos pestañas abiertas) reserven y marquen dos
  # leads a la vez. Si ya hay una marcación en curso, devolvemos queued:false
  # sin efecto. El lock se libera siempre en el ensure.
  def request_call
    unless acquire_dialing_lock
      Rails.logger.info "🔒 [Dialer] Marcación ya en curso, ignorando petición duplicada | cuenta=#{Current.account.id} usuario=#{current_user.id}"
      return render json: { queued: false, message: 'Dialing already in progress' }
    end

    begin
      perform_request_call
    ensure
      release_dialing_lock
    end
  end

  private def perform_request_call # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    agent = read_agent_state
    unless agent
      Rails.logger.info "🔴 [Dialer] Sin estado de agente en Redis | cuenta=#{Current.account.id} usuario=#{current_user.id}"
      return render json: { queued: false, message: 'Not connected' }
    end

    unless agent[:state_id].nil?
      Rails.logger.info "⏸️  [Dialer] Agente no disponible | estado=#{agent[:state_id]} usuario=#{current_user.id}"
      return render json: { queued: false, message: 'Agent not available' }
    end

    campaign = Current.account.jabvox_dialer_campaigns.find_by(id: agent[:campaign_id], status_jabvox: 'active')
    unless campaign
      Rails.logger.info "🔴 [Dialer] Sin campaña activa | campaña_id=#{agent[:campaign_id]} cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'No active campaign' }
    end

    unless campaign.in_schedule?
      Rails.logger.info "⏰ [Dialer] Campaña fuera de horario | campaña=#{campaign.name_jabvox} (id=#{campaign.id}) cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'Campaign out of schedule', out_of_schedule: true }
    end

    if agent[:extension].blank?
      Rails.logger.info "🔴 [Dialer] Agente sin extensión configurada | usuario=#{current_user.id} cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'No extension configured' }
    end

    config = Current.account.jabvox_voip_config
    if config&.host.blank?
      Rails.logger.info "🔴 [Dialer] Sin configuración VoIP | cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'No VoIP configuration' }
    end

    # Atomically pick + reserve the lead so two concurrent agents on the same
    # campaign can never grab the same one. The block resolves the dial number;
    # returning nil marks the reserved row as failed and we skip to the next call.
    skip_reason = nil
    lead, contact = Jabvox::DialerContactPickerService.new(Current.account, campaign).pick_and_reserve do |picked|
      phone = Jabvox::DialNumberResolver.resolve(
        lead: picked, field: campaign.dial_field_jabvox, prefix: campaign.dial_prefix_jabvox
      ).to_s
      if phone.blank?
        skip_reason = 'Lead sin número en el campo configurado'
        nil
      else
        # NO fijar attempts_jabvox aquí: el picker es la única fuente de verdad
        # del contador (lo incrementa en pick_and_reserve). Fijarlo a 0 aquí lo
        # reseteaba en cada marcación y max_retries nunca se aplicaba.
        { name_jabvox: picked.contact.name.to_s, phone_jabvox: phone,
          status_jabvox: 'calling' }
      end
    end

    unless lead
      Rails.logger.info "📭 [Dialer] Sin leads disponibles | campaña=#{campaign.name_jabvox} (id=#{campaign.id}) | " \
                        "filtro=#{campaign.management_state_ids_jabvox.inspect}"
      return render json: { queued: false, message: 'No pending contacts' }
    end
    if skip_reason
      Rails.logger.info "📭 [Dialer] #{skip_reason} | lead=#{lead.id}"
      return render json: { queued: false, message: skip_reason }
    end

    phone = contact.phone_jabvox
    log_originate(contact, campaign, agent[:extension])
    service = Jabvox::DialerService.new(config)
    service.prepare_agent_for_call("dialer_camp_#{campaign.id}", agent[:extension])
    result = service.originate_call(
      phone: phone,
      extension: agent[:extension].to_s,
      campaign: campaign,
      contact: contact,
      account: Current.account,
      user_id: current_user.id,
      caller_id: campaign.caller_id_jabvox.presence
    )
    if result[:success]
      Rails.logger.info "✅ [Dialer] Llamada iniciada | número=#{phone} campaña=#{campaign.name_jabvox} cuenta=#{Current.account.id}"
      assign_lead_to_agent(contact, current_user)
    else
      Rails.logger.info "❌ [Dialer] Fallo al marcar | número=#{phone} motivo=#{result[:message]} cuenta=#{Current.account.id}"
    end
    # Devolver a QUIÉN se está marcando para que el agente lo vea MIENTRAS suena
    # (en one_by_one no hay call_assigned hasta que contestan). El frontend lo
    # pinta en la tarjeta de "Marcando…".
    crm = lead.contact
    render json: result.merge(
      dialer_contact_id: contact.id,
      contact_id: lead.contact_id,
      contact_name: crm&.name.to_s,
      contact_phone: phone,
      lead_number: lead.lead_number
    )
  end

  def end_call
    contact = Current.account.jabvox_dialer_campaign_contacts
                     .find_by(id: params[:dialer_contact_id], status_jabvox: 'calling')
    contact&.update!(status_jabvox: 'no_answer')
    clear_in_call_marker
    hangup_agent_call
    # account_id es OBLIGATORIO: el frontend descarta en silencio (isAValidEvent)
    # cualquier evento cuyo data.account_id no coincida con la cuenta actual.
    ActionCable.server.broadcast(
      current_user.pubsub_token,
      { event: 'jabvox.dialer.call_ended', data: { account_id: Current.account.id,
                                                   user_id: current_user.id,
                                                   dialer_contact_id: params[:dialer_contact_id] } }
    )
    head :ok
  end

  private

  def sync_queue_membership(campaign_id, extension, add:)
    return unless campaign_id.present? && extension.present?

    config = Current.account.jabvox_voip_config
    return unless config&.host.present?

    queue_name = "dialer_camp_#{campaign_id}"
    service = Jabvox::DialerService.new(config)
    add ? service.add_to_queue(queue_name, extension) : service.remove_from_queue(queue_name, extension)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] sync_queue_membership failed | #{e.message}"
  end

  def sync_queue_pause(campaign_id, extension, paused:)
    return unless campaign_id.present? && extension.present?

    config = Current.account.jabvox_voip_config
    return unless config&.host.present?

    Jabvox::DialerService.new(config).pause_in_queue("dialer_camp_#{campaign_id}", extension, paused: paused)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] sync_queue_pause failed | #{e.message}"
  end

  def hangup_agent_call
    agent_data = read_agent_state
    extension   = agent_data&.dig(:extension)
    campaign_id = agent_data&.dig(:campaign_id)
    return unless extension.present?

    config = Current.account.jabvox_voip_config
    return unless config&.host.present?

    service = Jabvox::DialerService.new(config)
    service.hangup_extension(extension)
    service.pause_in_queue("dialer_camp_#{campaign_id}", extension, paused: true) if campaign_id.present?
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] hangup_agent_call failed | #{e.message}"
  end

  # When a dialer call reaches the agent, the lead is auto-assigned to them so
  # they can manage it from Leads. Uses update_columns to skip validations/
  # callbacks — assignment must never fail because of an unrelated lead
  # validation, and we log if it somehow does instead of swallowing silently.
  def assign_lead_to_agent(contact, user)
    return unless contact.contact_id

    lead = Current.account.jabvox_leads.find_by(contact_id: contact.contact_id)
    return unless lead

    # rubocop:disable Rails/SkipsModelValidations
    lead.update_columns(assignee_id: user.id, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    # The agent who took the call now owns the lead — its open conversations follow.
    Jabvox::LeadConversationAssignmentSync.new(Current.account).sync_lead(lead, user)
  rescue StandardError => e
    Rails.logger.error("[Dialer] assign_lead_to_agent failed | lead_contact=#{contact.contact_id} #{e.class}: #{e.message}")
  end

  def log_connect(account_id, user_id, extension, campaign_id)
    Rails.logger.info "🎧 [Dialer] Agente conectado | cuenta=#{account_id} usuario=#{user_id} extensión=#{extension} campaña=#{campaign_id}"
  end

  def log_originate(contact, campaign, extension)
    Rails.logger.info "📞 [Dialer] Marcando | número=#{contact.phone_jabvox} contacto=#{contact.name_jabvox} " \
                      "extensión=#{extension} campaña=#{campaign.name_jabvox} (id=#{campaign.id}) cuenta=#{Current.account.id}"
  end

  def require_admin
    render json: { error: 'forbidden' }, status: :forbidden unless current_user.administrator?
  end

  # Agents operating the dialer need either grant; admin-only actions are
  # additionally guarded by require_admin. Admins always pass. Users on a
  # standard role (no custom role) keep historical access — the per-user
  # dialer-access switch (jabvox_dialer_accesses) is the real gate for them.
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?
    return if jabvox_can?('jabvox_dialer_use') || jabvox_can?('jabvox_dialer_manage')

    render json: { error: I18n.t('jabvox.permissions.denied', default: 'You do not have permission for this action.') },
           status: :forbidden
  end

  # Lock de marcación por agente. SET NX EX es atómico: solo un request lo
  # adquiere; los solapados fallan y salen sin marcar. TTL corto para que un
  # proceso que muera a mitad no bloquee al agente más que un ciclo de polling.
  DIALING_LOCK_TTL = 30

  def dialing_lock_key
    "jabvox_dialer_dialing_#{Current.account.id}_#{current_user.id}"
  end

  def acquire_dialing_lock
    Redis::Alfred.set(dialing_lock_key, Time.current.to_i, nx: true, ex: DIALING_LOCK_TTL)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] acquire_dialing_lock failed | #{e.message}"
    # Ante un fallo de Redis preferimos no bloquear la marcación (el picker con
    # advisory lock sigue evitando doble reserva del mismo lead).
    true
  end

  def release_dialing_lock
    Redis::Alfred.delete(dialing_lock_key)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] release_dialing_lock failed | #{e.message}"
  end

  def agent_cache_key_for(uid = current_user.id)
    "jabvox_dialer_agent_#{Current.account.id}_#{uid}"
  end

  def agents_set_key
    "jabvox_dialer_connected_#{Current.account.id}"
  end

  def read_agent_state
    read_agent_state_for(current_user.id)
  end

  def read_agent_state_for(uid)
    raw = Redis::Alfred.get(agent_cache_key_for(uid))
    raw ? JSON.parse(raw, symbolize_names: true) : nil
  rescue StandardError
    nil
  end

  def write_agent_state(data)
    Redis::Alfred.setex(agent_cache_key_for, data.to_json, AGENT_TTL)
  end

  # Renueva el TTL sin tocar el contenido (evita la race con el AMI listener).
  def touch_agent_state
    Redis::Alfred.expire(agent_cache_key_for, AGENT_TTL)
  rescue StandardError
    nil
  end

  # Quita la marca de "en llamada" del estado Redis del agente (la pone el AMI
  # listener al asignar la llamada) para que el reporte de agentes vuelva a
  # mostrar "esperando llamada" al colgar desde el frontend.
  def clear_in_call_marker
    data = read_agent_state
    return unless data && data[:in_call_contact_id].present?

    data.delete(:in_call_contact_id)
    data[:state_changed_at] = Time.current.to_i
    write_agent_state(data)
    # Al colgar desde el frontend el agente vuelve a estar disponible (o en pausa
    # si tenía un estado activo): registrar la transición para el reporte.
    record_agent_state(data[:state_id].present? ? 'paused' : 'waiting')
  rescue StandardError
    nil
  end

  def record_agent_state(state)
    Jabvox::DialerAgentStateLogger.record(account_id: Current.account.id, user_id: current_user.id, state: state)
  end

  def remove_agent_state
    Redis::Alfred.delete(agent_cache_key_for)
  end

  # Connected-agent tracking uses a native Redis SET (SADD/SREM/SMEMBERS) instead
  # of a read-modify-write JSON array. SADD/SREM are atomic, so many agents
  # connecting/disconnecting concurrently can never clobber each other's updates
  # (the old JSON-array approach lost writes under load — a real risk in
  # predictive mode with dozens of agents toggling at once).
  def connected_agent_ids
    Redis::Alfred.smembers(agents_set_key).map(&:to_i)
  rescue StandardError
    []
  end

  def register_connected_agent(uid)
    # One-time transition: an old deploy stored this key as a JSON string, so a
    # SADD would raise WRONGTYPE. Drop any non-set value before adding.
    Redis::Alfred.delete(agents_set_key) if Redis::Alfred.type(agents_set_key) != 'set'
    Redis::Alfred.sadd(agents_set_key, uid.to_i)
    Redis::Alfred.expire(agents_set_key, 2.hours.to_i)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] register_connected_agent failed | #{e.message}"
  end

  def unregister_connected_agent(uid)
    Redis::Alfred.srem(agents_set_key, uid.to_i)
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] unregister_connected_agent failed | #{e.message}"
  end
end
