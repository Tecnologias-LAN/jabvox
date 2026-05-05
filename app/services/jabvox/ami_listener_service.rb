require 'socket'

module Jabvox
  class AmiListenerService # rubocop:disable Metrics/ClassLength
    RECONNECT_DELAY = 10
    READ_TIMEOUT    = 35

    def initialize(account_id)
      @account_id      = account_id
      @active_channels = {}
      @socket          = nil
    end

    def run
      loop do
        run_once
      rescue StandardError => e
        Rails.logger.error "❌ [AmiListener] account=#{@account_id} reconnecting in #{RECONNECT_DELAY}s | #{e.message}"
        sleep RECONNECT_DELAY
      end
    end

    private

    def run_once
      config = Account.find(@account_id).jabvox_voip_config
      raise 'No VoIP config' unless config&.host.present?

      @config = config
      @socket = TCPSocket.new(config.host, config.port.to_i)
      @socket.gets # banner
      login(@socket, config)
      Rails.logger.info "✅ [AmiListener] account=#{@account_id} connected to #{config.host}"
      listen
    ensure
      @socket&.close rescue nil
      @socket = nil
    end

    def login(socket, config)
      socket.write("Action: Login\r\nUsername: #{config.username}\r\nSecret: #{config.password}\r\nEvents: on\r\n\r\n")
      resp = read_response(socket)
      raise "AMI Login failed: #{resp['message']}" unless resp['response'] == 'Success'
    end

    def listen
      loop do
        ready = IO.select([@socket], nil, nil, READ_TIMEOUT)
        unless ready
          @socket.write("Action: Ping\r\n\r\n")
          next
        end
        event = read_response(@socket)
        next if event.empty?

        dispatch_event(event)
      end
    end

    def dispatch_event(event)
      evt_name = event['event'].to_s
      Rails.logger.debug "🔎 [AmiListener] event=#{evt_name}" if evt_name.present?

      case evt_name.downcase
      when 'agentconnect'
        handle_agent_connect(event)
      when 'agentcomplete'
        handle_agent_complete(event)
      when 'hangup'
        handle_hangup(event)
      end
    end

    def handle_agent_connect(event) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      Rails.logger.info "🔎 [AmiListener] AgentConnect fields: #{event.inspect}"
      queue = event['queue'].to_s
      return unless queue.start_with?('dialer_camp_')

      caller_channel = event['channel'].to_s
      dest_channel   = event['destchannel'].to_s
      # Issabel sends member interface as 'interface'; upstream Asterisk uses 'member'
      member    = event['interface'].presence || event['member'].to_s
      extension = strip_sip_prefix(member)
      return if caller_channel.blank? || extension.blank?

      contact_id = getvar_on_existing(caller_channel, 'JABVOX_CONTACT_ID')
      contact_id ||= getvar_on_existing(dest_channel, 'JABVOX_CONTACT_ID') if dest_channel.present?
      user_id_s  = getvar_on_existing(caller_channel, 'JABVOX_AGENT_USER_ID')
      user_id_s  ||= getvar_on_existing(dest_channel, 'JABVOX_AGENT_USER_ID') if dest_channel.present?

      Rails.logger.info "🔍 [AmiListener] AgentConnect Getvar | contact_id=#{contact_id.inspect} user_id=#{user_id_s.inspect} channel=#{caller_channel}"

      return unless contact_id.present? && user_id_s.present?

      contact_id  = contact_id.to_i
      user_id     = user_id_s.to_i
      campaign_id = parse_campaign_id(queue)

      Rails.logger.info "📞 [AmiListener] AgentConnect | account=#{@account_id} ext=#{extension} queue=#{queue} user=#{user_id}"

      info = { contact_id: contact_id, user_id: user_id, campaign_id: campaign_id,
               extension: extension, caller_channel: caller_channel, dest_channel: dest_channel }
      @active_channels[caller_channel] = info
      @active_channels[dest_channel]   = info if dest_channel.present?

      broadcast_call_assigned(user_id, contact_id, campaign_id)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_agent_connect failed | #{e.message}"
    end

    # Reuses the existing authenticated socket — avoids TCP+login overhead per Getvar.
    # If events arrive before the Response, we dispatch them and keep looking.
    def getvar_on_existing(channel, variable)
      send_action(@socket, 'Getvar', channel: channel, variable: variable)
      20.times do
        resp = read_response(@socket)
        # AMI lowercases keys in our parser; 'value' is the Getvar result
        return resp['value'] if resp.key?('response')
        # An event arrived before our response — dispatch it, keep waiting
        dispatch_event(resp) if resp.key?('event')
      end
      nil
    rescue StandardError
      nil
    end

    # AgentComplete fires when queue call ends — use as primary call_ended trigger.
    # Falls back to extension lookup in Redis if channel map isn't populated yet.
    def handle_agent_complete(event) # rubocop:disable Metrics/MethodLength
      queue     = event['queue'].to_s
      member    = event['interface'].presence || event['member'].to_s
      extension = strip_sip_prefix(member)

      Rails.logger.info "🔎 [AmiListener] AgentComplete | queue=#{queue} member=#{member} ext=#{extension}"
      return unless queue.start_with?('dialer_camp_') && extension.present?

      campaign_id = parse_campaign_id(queue)

      # Try channel map first
      channel = event['channel'].to_s
      info    = @active_channels.delete(channel)
      if info
        @active_channels.delete(info[:caller_channel])
        @active_channels.delete(info[:dest_channel])
        broadcast_call_ended_for(info[:user_id], info[:contact_id], campaign_id, extension)
        return
      end

      # Fallback: find agent by extension in Redis
      user_id, state = find_agent_by_extension(extension)
      return unless user_id && state

      broadcast_call_ended_for(user_id, nil, campaign_id, extension, state)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_agent_complete failed | #{e.message}"
    end

    def handle_hangup(event)
      channel = event['channel'].to_s
      info    = @active_channels.delete(channel)
      return unless info

      @active_channels.delete(info[:caller_channel])
      @active_channels.delete(info[:dest_channel])
      broadcast_call_ended_for(info[:user_id], info[:contact_id], info[:campaign_id], info[:extension])
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_hangup failed | #{e.message}"
    end

    def broadcast_call_ended_for(user_id, contact_id, campaign_id, extension, state = nil) # rubocop:disable Metrics/MethodLength
      state ||= begin
        raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account_id}_#{user_id}")
        raw ? JSON.parse(raw, symbolize_names: true) : nil
      end
      return unless state

      pubsub_token = state[:pubsub_token]
      return if pubsub_token.blank?

      Rails.logger.info "📵 [AmiListener] call_ended | account=#{@account_id} ext=#{extension} user=#{user_id}"

      Jabvox::DialerService.new(@config).pause_in_queue("dialer_camp_#{campaign_id}", extension, paused: true) if campaign_id.present?

      ActionCable.server.broadcast(
        pubsub_token,
        { event: 'jabvox.dialer.call_ended', data: { account_id: @account_id, user_id: user_id, dialer_contact_id: contact_id } }
      )
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] broadcast_call_ended_for failed | #{e.message}"
    end

    def broadcast_call_assigned(user_id, dialer_contact_id, campaign_id) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      account  = Account.find(@account_id)
      contact  = account.jabvox_dialer_campaign_contacts.find_by(id: dialer_contact_id)
      return unless contact

      crm      = Contact.find_by(id: contact.contact_id, account_id: @account_id)
      campaign = account.jabvox_dialer_campaigns.find_by(id: campaign_id)
      lead     = account.jabvox_leads.find_by(contact_id: contact.contact_id)
      return unless crm && campaign

      raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account_id}_#{user_id}")
      return unless raw

      state        = JSON.parse(raw, symbolize_names: true)
      pubsub_token = state[:pubsub_token]
      return if pubsub_token.blank?

      conversation_id = find_or_create_conversation(account, crm, campaign)

      fv   = field_vis(account, user_id)
      data = {
        account_id:         @account_id,
        dialer_contact_id:  contact.id,
        user_id:            user_id,
        contact_name:       fv['name']    != false ? crm.name.to_s         : '***',
        contact_phone:      fv['phone']   != false ? contact.phone_jabvox  : '***',
        contact_email:      fv['email']   != false ? crm.email.to_s        : '***',
        contact_country:    fv['country'] != false ? crm.country_code.to_s : '***',
        contact_id:         contact.contact_id,
        lead_id:            lead&.id,
        lead_number:        lead&.lead_number,
        affiliate_name:     lead&.jabvox_affiliate&.name.to_s,
        campaign_name:      lead&.jabvox_campaign&.name_jabvox.to_s,
        conversation_id:    conversation_id,
        wrapup_seconds:     campaign.wrapup_time_jabvox.to_i,
        management_history: fetch_mgmt_history(account, contact.contact_id)
      }

      ActionCable.server.broadcast(pubsub_token, { event: 'jabvox.dialer.call_assigned', data: data })
      Rails.logger.info "📨 [AmiListener] call_assigned broadcast | account=#{@account_id} user=#{user_id} contact=#{dialer_contact_id}"
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] broadcast_call_assigned failed | #{e.message}"
    end

    def find_or_create_conversation(account, crm, campaign)
      existing = account.conversations.where(contact_id: crm.id).order(id: :desc).first
      return existing.id if existing

      inbox_id = (campaign.inbox_ids_jabvox || []).compact.map(&:to_i).find { |id| id.positive? } ||
                 account.inboxes.first&.id
      return nil unless inbox_id

      inbox = Inbox.find_by(id: inbox_id, account_id: account.id)
      return nil unless inbox

      contact_inbox = ContactInbox.find_or_create_by!(contact: crm, inbox: inbox) do |ci|
        ci.source_id = SecureRandom.uuid
      end

      Conversation.create!(
        account_id:       account.id,
        inbox_id:         inbox.id,
        contact_id:       crm.id,
        contact_inbox_id: contact_inbox.id
      ).id
    rescue StandardError => e
      Rails.logger.warn "⚠️ [AmiListener] find_or_create_conversation failed | #{e.message}"
      nil
    end

    def field_vis(account, user_id)
      records = account.jabvox_field_visibilities.where(user_id: user_id)
      JabvoxFieldVisibility::FIELDS.index_with { true }.merge(
        records.each_with_object({}) { |v, h| h[v.field_name] = v.can_view }
      )
    end

    def fetch_mgmt_history(account, contact_id, limit: 8)
      return [] unless contact_id

      Message.joins(:conversation)
             .where(conversations: { account_id: account.id, contact_id: contact_id })
             .where(private: true)
             .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
             .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
             .order(id: :desc)
             .limit(limit)
             .map do |msg|
               { state_name:  msg.content_attributes['jabvox_management_state_name'],
                 state_color: msg.content_attributes['jabvox_management_state_color'],
                 note:        msg.content,
                 created_at:  msg.created_at.strftime('%d/%m %H:%M') }
             end
    rescue StandardError
      []
    end

    def strip_sip_prefix(member)
      member.sub(/\ASIP\//i, '').sub(/\APJSIP\//i, '')
    end

    def parse_campaign_id(queue)
      queue.sub('dialer_camp_', '').to_i
    end

    def send_action(socket, action, **params)
      msg = "Action: #{action}\r\n"
      params.each { |key, val| msg += "#{key}: #{val}\r\n" }
      msg += "\r\n"
      socket.write(msg)
    end

    def read_response(socket)
      result = {}
      loop do
        line = socket.gets
        raise 'AMI connection closed' if line.nil?

        line = line.chomp
        break if line.empty?

        key, val = line.split(': ', 2)
        result[key.downcase] = val if key && val
      end
      result
    end
  end
end
