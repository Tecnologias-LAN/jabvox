# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::DialerAccessesController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
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
    agent_data = {
      user_id: current_user.id,
      campaign_id: campaign_id,
      extension: user_ext&.extension_jabvox,
      state_id: nil,
      connected_at: Time.current.to_i,
      pubsub_token: current_user.pubsub_token
    }
    write_agent_state(agent_data)
    register_connected_agent(current_user.id)
    sync_queue_membership(campaign_id, user_ext&.extension_jabvox, add: true)
    log_connect(Current.account.id, current_user.id, user_ext&.extension_jabvox, campaign_id)
    render json: { extension: user_ext&.extension_jabvox }
  end

  def disconnect
    data = read_agent_state
    sync_queue_membership(data&.dig(:campaign_id), data&.dig(:extension), add: false) if data
    remove_agent_state
    unregister_connected_agent(current_user.id)
    head :no_content
  end

  def update_state
    data = read_agent_state
    return head :not_found unless data

    paused = params[:state_id].present?
    data[:state_id] = params[:state_id].presence&.to_i
    write_agent_state(data)
    sync_queue_pause(data[:campaign_id], data[:extension], paused: paused)
    head :ok
  end

  def heartbeat
    data = read_agent_state
    return head :not_found unless data

    write_agent_state(data)
    head :ok
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

  def request_call # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
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

    if agent[:extension].blank?
      Rails.logger.info "🔴 [Dialer] Agente sin extensión configurada | usuario=#{current_user.id} cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'No extension configured' }
    end

    config = Current.account.jabvox_voip_config
    if config&.host.blank?
      Rails.logger.info "🔴 [Dialer] Sin configuración VoIP | cuenta=#{Current.account.id}"
      return render json: { queued: false, message: 'No VoIP configuration' }
    end

    lead = Jabvox::DialerContactPickerService.new(Current.account, campaign).pick
    unless lead
      Rails.logger.info "📭 [Dialer] Sin leads disponibles | campaña=#{campaign.name_jabvox} (id=#{campaign.id}) | " \
                        "filtro=#{campaign.management_state_ids_jabvox.inspect}"
      return render json: { queued: false, message: 'No pending contacts' }
    end

    crm_contact = lead.contact
    phone = crm_contact.phone_number.to_s.strip
    contact = JabvoxDialerCampaignContact.create!(
      account_id: Current.account.id,
      jabvox_dialer_campaign_id: campaign.id,
      contact_id: lead.contact_id,
      name_jabvox: crm_contact.name.to_s,
      phone_jabvox: phone,
      status_jabvox: 'calling',
      attempts_jabvox: 0,
      last_attempt_at_jabvox: Time.current
    )

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
    render json: result.merge(dialer_contact_id: contact.id)
  end

  def end_call
    contact = Current.account.jabvox_dialer_campaign_contacts
                     .find_by(id: params[:dialer_contact_id], status_jabvox: 'calling')
    contact&.update!(status_jabvox: 'no_answer')
    hangup_agent_call
    ActionCable.server.broadcast(
      current_user.pubsub_token,
      { event: 'jabvox.dialer.call_ended', data: { user_id: current_user.id,
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

  def assign_lead_to_agent(contact, user)
    return unless contact.contact_id

    lead = Current.account.jabvox_leads.find_by(contact_id: contact.contact_id)
    lead&.update(assignee_id: user.id)
  rescue StandardError
    nil
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

  def remove_agent_state
    Redis::Alfred.delete(agent_cache_key_for)
  end

  def connected_agent_ids
    raw = Redis::Alfred.get(agents_set_key)
    raw ? JSON.parse(raw) : []
  rescue StandardError
    []
  end

  def register_connected_agent(uid)
    ids = connected_agent_ids
    Redis::Alfred.set(agents_set_key, (ids + [uid.to_i]).uniq.to_json, ex: 2.hours.to_i)
  end

  def unregister_connected_agent(uid)
    ids = connected_agent_ids
    Redis::Alfred.set(agents_set_key, (ids - [uid.to_i]).to_json, ex: 2.hours.to_i)
  end
end
