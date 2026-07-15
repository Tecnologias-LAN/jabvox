require 'socket'
require 'timeout'

module Jabvox
  class VoipService
    AMI_TIMEOUT = 10

    def initialize(config)
      @config = config
    end

    def originate(extension:, phone:, caller_id: nil)
      phone = Jabvox::PhoneNormalizer.for_dialing(phone)
      with_ami do |socket|
        params = {
          channel: "SIP/#{extension}",
          context: @config.context,
          exten: phone,
          priority: 1,
          timeout: 30_000,
          async: 'true'
        }
        params[:callerid] = caller_id if caller_id.present?

        send_action(socket, 'Originate', **params)
        orig_resp = read_response(socket)
        { success: orig_resp['response'] == 'Success', message: orig_resp['message'] || orig_resp['response'] }
      end
    end

    # Click-to-call: rings the agent's extension first, then dials the contact.
    # Inherited __CTCALL_* variables let the AMI listener correlate the Hangup
    # back to the call log (and capture the recording uniqueid).
    def originate_click_to_call(extension:, phone:, call_log_id:, user_id:, caller_id: nil)
      phone = Jabvox::PhoneNormalizer.for_dialing(phone)
      with_ami do |socket|
        params = {
          channel: "SIP/#{extension}",
          context: @config.context,
          exten: phone,
          priority: 1,
          timeout: 30_000,
          async: 'true',
          'Variable' => ["__CTCALL_ID=#{call_log_id}", "__CTCALL_USER=#{user_id}", "__CTCALL_ACCOUNT=#{@config.account_id}"]
        }
        params[:callerid] = caller_id if caller_id.present?

        # TEMP DIAG: exactly what we send to AMI for the click-to-call originate
        Rails.logger.info "🔧 [DIAG] CTC originate channel=SIP/#{extension} exten=#{phone} vars=#{params['Variable'].inspect}"
        send_action(socket, 'Originate', **params)
        orig_resp = read_response(socket)
        Rails.logger.info "🔧 [DIAG] CTC originate resp=#{orig_resp['response'].inspect} msg=#{orig_resp['message'].inspect}"
        { success: orig_resp['response'] == 'Success', message: orig_resp['message'] || orig_resp['response'] }
      end
    end

    # Hangs up a specific click-to-call channel, identified by its CTCALL_ID and validated
    # to belong to THIS account (CTCALL_ACCOUNT). This is channel-specific — it never hangs
    # up by bare "SIP/<ext>", so colliding extensions on a shared PBX across accounts are safe.
    def hangup(call_log_id:, account_id: nil)
      account_id ||= @config.account_id
      with_ami do |socket|
        match = find_channel_for_call_log(socket, call_log_id, account_id)
        # No matching channel on this account's PBX — nothing safe to hang up.
        next { success: true, message: 'No active channel' } unless match

        send_action(socket, 'Hangup', channel: match[:channel])
        resp = read_response(socket)
        { success: resp['response'] == 'Success', message: resp['message'] || resp['response'] }
      end
    end

    # Early uniqueid capture: right after originate, look up the agent channel for this
    # call_log (by CTCALL_ID + account) and return its Asterisk uniqueid, or nil. This makes
    # the CDR link independent of the Hangup event ever firing.
    def channel_uniqueid(call_log_id:, account_id: nil)
      account_id ||= @config.account_id
      result = with_ami do |socket|
        find_channel_for_call_log(socket, call_log_id, account_id)&.dig(:uniqueid)
      end
      result.is_a?(String) ? result.presence : nil
    rescue StandardError
      nil
    end

    private

    # Scans AMI Status for the channel whose CTCALL_ID matches and whose CTCALL_ACCOUNT is
    # this account, returning { channel:, uniqueid: } or nil.
    def find_channel_for_call_log(socket, call_log_id, account_id)
      send_action(socket, 'Status', Variables: 'CTCALL_ID,CTCALL_ACCOUNT')
      match = nil
      80.times do
        block = read_status_block(socket)
        break if block.nil?
        break if block[:event] == 'StatusComplete'
        next unless block[:event] == 'Status'

        vars = block[:variables]
        if vars['CTCALL_ID'].to_s == call_log_id.to_s && vars['CTCALL_ACCOUNT'].to_s == account_id.to_s
          match = { channel: block[:channel], uniqueid: block[:uniqueid] }
          break
        end
      end
      match
    end

    # Reads one AMI block (until a blank line) as raw "Key: Value" pairs, preserving the
    # repeated "Variable:" lines a Status event emits (read_response would overwrite them).
    def read_status_block(socket)
      lines = read_block_lines(socket)
      return nil if lines.nil?

      first = ->(key) { lines.find { |k, _| k == key }&.last }
      {
        event: first.call('Event'),
        channel: first.call('Channel'),
        uniqueid: first.call('Uniqueid'),
        variables: extract_variables(lines)
      }
    end

    # Returns the block's [key, value] pairs, or nil if the socket closed.
    def read_block_lines(socket)
      lines = []
      loop do
        line = socket.gets&.chomp
        return nil if line.nil?
        break if line.empty?

        key, val = line.split(': ', 2)
        lines << [key, val] if key && val
      end
      lines
    end

    def extract_variables(lines)
      lines.each_with_object({}) do |(key, val), vars|
        next unless key == 'Variable' && val.include?('=')

        k, v = val.split('=', 2)
        vars[k] = v
      end
    end

    def with_ami
      Timeout.timeout(AMI_TIMEOUT) do
        socket = TCPSocket.new(@config.host, @config.port.to_i)
        socket.gets # read AMI banner
        send_action(socket, 'Login', username: @config.username, secret: @config.password, events: 'off')
        login_resp = read_response(socket)
        raise "AMI Login failed: #{login_resp['message']}" unless login_resp['response'] == 'Success'

        result = yield socket
        socket.close
        result
      end
    rescue Timeout::Error
      { success: false, message: 'Connection timeout' }
    rescue StandardError => e
      { success: false, message: e.message }
    end

    def send_action(socket, action, **params)
      msg = "Action: #{action}\r\n"
      params.each do |key, val|
        # AMI needs ONE "Variable:" line per channel variable. Passing several as
        # a comma-joined string makes Asterisk treat the whole thing as a single
        # variable value, so pass an Array and we emit repeated lines.
        if val.is_a?(Array)
          val.each { |v| msg += "#{key}: #{v}\r\n" }
        else
          msg += "#{key}: #{val}\r\n"
        end
      end
      msg += "\r\n"
      socket.write(msg)
    end

    def read_response(socket)
      result = {}
      loop do
        line = socket.gets&.chomp
        break if line.nil? || line.empty?
        key, val = line.split(': ', 2)
        result[key.downcase] = val if key && val
      end
      result
    end
  end
end
