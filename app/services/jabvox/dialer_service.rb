require 'socket'
require 'timeout'

class Jabvox::DialerService
  AMI_TIMEOUT = 15

  def initialize(config)
    @config = config
  end

  def originate_call(phone:, extension:, campaign:, contact:, account:, caller_id: nil, user_id: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    context = @config.dialer_context.presence || @config.context
    result = { success: false, message: 'Connection error' }
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        params = build_originate_params(phone, extension, context, caller_id, campaign, contact, user_id)
        Rails.logger.info "📡 [Dialer] AMI Originate | host=#{@config.host}:#{@config.port} " \
                          "channel=#{params[:channel]} context=#{params[:context]} exten=#{params[:exten]} " \
                          "callerid=#{params[:callerid].inspect} vars=#{params[:variable]}"
        send_action(socket, 'Originate', **params)
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] AMI Response | response=#{resp['response']} message=#{resp['message']}"
        result = { success: resp['response'] == 'Success', message: resp['message'] || resp['response'] }
      end
    end
    persist_call(contact, campaign, account, phone, result[:success])
    result
  rescue Timeout::Error
    persist_call(contact, campaign, account, phone, false)
    { success: false, message: 'Connection timeout' }
  rescue StandardError => e
    persist_call(contact, campaign, account, phone, false)
    { success: false, message: e.message }
  end

  # Creates or replaces the queue in queues.conf and reloads app_queue.so.
  # Uses DelCat+NewCat so it is idempotent — safe to call on every campaign save.
  def ensure_queue_exists(queue_name)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        resp = write_queue_config(socket, queue_name)
        Rails.logger.info "📡 [Dialer] Queue ensured | queue=#{queue_name} response=#{resp['response']} message=#{resp['message']}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] ensure_queue_exists failed | queue=#{queue_name} error=#{e.message}"
  end

  def add_to_queue(queue_name, extension)
    # Ensure queue exists on a separate connection before adding the member.
    # Also handles campaigns created before provisioning code was deployed.
    ensure_queue_exists(queue_name)
    sleep(1) # allow app_queue.so reload to complete before QueueAdd
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueAdd',
                    queue: queue_name,
                    interface: "SIP/#{extension}",
                    penalty: 0,
                    paused: 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueAdd | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueueAdd failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  def remove_from_queue(queue_name, extension)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueRemove',
                    queue: queue_name,
                    interface: "SIP/#{extension}")
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueRemove | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueueRemove failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  def hangup_extension(extension)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        channel = find_active_channel(socket, extension)
        unless channel
          Rails.logger.warn "⚠️ [Dialer] hangup_extension: no active channel for SIP/#{extension}"
          return
        end
        send_action(socket, 'Hangup', channel: channel)
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] Hangup | channel=#{channel} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] hangup_extension failed | ext=#{extension} error=#{e.message}"
  end

  def prepare_agent_for_call(queue_name, extension)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueAdd', queue: queue_name, interface: "SIP/#{extension}", penalty: 0, paused: 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueAdd (prepare) | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
        send_action(socket, 'QueuePause', queue: queue_name, interface: "SIP/#{extension}", paused: 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueUnpause (prepare) | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] prepare_agent_for_call failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  def getvar(channel, variable)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'Getvar', channel: channel, variable: variable)
        resp = read_response(socket)
        return resp['value']
      end
    end
  rescue StandardError
    nil
  end

  def pause_in_queue(queue_name, extension, paused:)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueuePause',
                    queue: queue_name,
                    interface: "SIP/#{extension}",
                    paused: paused ? 'true' : 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueuePause | queue=#{queue_name} ext=#{extension} paused=#{paused} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueuePause failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  private

  def with_ami_connection
    socket = TCPSocket.new(@config.host, @config.port.to_i)
    socket.gets
    login_ami(socket)
    yield socket
  ensure
    socket&.close
  end

  def login_ami(socket)
    send_action(socket, 'Login',
                username: @config.username,
                secret: @config.password,
                events: 'off')
    login_resp = read_response(socket)
    raise "AMI Login failed: #{login_resp['message']}" unless login_resp['response'] == 'Success'
  end

  # Writes queue config using UpdateConfig (no Command/queue show needed).
  # DelCat removes existing section (no-op if absent), NewCat creates fresh.
  # reload: app_queue.so applies the change immediately.
  def write_queue_config(socket, queue_name) # rubocop:disable Metrics/MethodLength
    # Step 1: try to delete existing category — ignore error if it doesn't exist yet
    socket.write("Action: UpdateConfig\r\n" \
                 "srcfilename: queues_custom.conf\r\n" \
                 "dstfilename: queues_custom.conf\r\n" \
                 "reload: no\r\n" \
                 "Action-000000: DelCat\r\n" \
                 "Cat-000000: #{queue_name}\r\n" \
                 "\r\n")
    read_response(socket)

    # Step 2: create category fresh with all required settings + reload
    socket.write("Action: UpdateConfig\r\n" \
                 "srcfilename: queues_custom.conf\r\n" \
                 "dstfilename: queues_custom.conf\r\n" \
                 "reload: app_queue.so\r\n" \
                 "Action-000000: NewCat\r\n" \
                 "Cat-000000: #{queue_name}\r\n" \
                 "Action-000001: Append\r\n" \
                 "Cat-000001: #{queue_name}\r\n" \
                 "Var-000001: strategy\r\n" \
                 "Value-000001: ringall\r\n" \
                 "Action-000002: Append\r\n" \
                 "Cat-000002: #{queue_name}\r\n" \
                 "Var-000002: timeout\r\n" \
                 "Value-000002: 30\r\n" \
                 "Action-000003: Append\r\n" \
                 "Cat-000003: #{queue_name}\r\n" \
                 "Var-000003: autopause\r\n" \
                 "Value-000003: no\r\n" \
                 "Action-000004: Append\r\n" \
                 "Cat-000004: #{queue_name}\r\n" \
                 "Var-000004: joinempty\r\n" \
                 "Value-000004: yes\r\n" \
                 "\r\n")
    read_response(socket)
  end

  def build_originate_params(phone, extension, context, caller_id, campaign, contact, user_id) # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
    trunk   = @config.dialer_trunk.presence
    channel = trunk ? "SIP/#{phone}@#{trunk}" : "SIP/#{extension}"
    exten   = trunk ? 's' : phone
    queue   = "dialer_camp_#{campaign.id}"

    params = {
      channel: channel,
      context: context,
      exten: exten,
      priority: 1,
      timeout: 30_000,
      async: 'true',
      variable: "DIALER_QUEUE=#{queue}," \
                "__JABVOX_CONTACT_ID=#{contact.id}," \
                "__JABVOX_ACCOUNT_ID=#{campaign.account_id}," \
                "__JABVOX_AGENT_USER_ID=#{user_id}," \
                "JABVOX_CAMPAIGN_ID=#{campaign.id}"
    }
    params[:callerid] = caller_id.presence || "#{contact.name_jabvox} <0000>"
    params
  end

  def persist_call(contact, campaign, account, phone, success)
    contact.update!(
      status_jabvox: success ? 'calling' : 'failed',
      attempts_jabvox: contact.attempts_jabvox + 1,
      last_attempt_at_jabvox: Time.current
    )
    account.jabvox_dialer_call_logs.create!(
      jabvox_dialer_campaign: campaign,
      jabvox_dialer_campaign_contact: contact,
      phone_jabvox: phone,
      status_jabvox: success ? 'initiated' : 'failed',
      started_at_jabvox: Time.current
    )
  end

  # Reads channel list from AMI Status and returns the exact channel name
  # for the given extension (e.g. "SIP/1010-00000abc").
  def find_active_channel(socket, extension)
    send_action(socket, 'Status')
    # Consume the initial "Channel status will follow" header
    read_response(socket)
    # Iterate Status events until StatusComplete or empty response
    100.times do
      event = read_response(socket)
      break if event.empty? || event['event']&.casecmp?('statuscomplete')
      next unless event['event']&.casecmp?('status')
      ch = event['channel'].to_s
      return ch if ch.start_with?("SIP/#{extension}-") || ch.start_with?("PJSIP/#{extension}-")
    end
    nil
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
      line = socket.gets&.chomp
      break if line.blank?

      key, val = line.split(': ', 2)
      result[key.downcase] = val if key && val
    end
    result
  end
end
