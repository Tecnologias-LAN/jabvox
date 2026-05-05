require 'socket'
require 'timeout'

module Jabvox
  class VoipService
    AMI_TIMEOUT = 10

    def initialize(config)
      @config = config
    end

    def originate(extension:, phone:, caller_id: nil)
      Timeout.timeout(AMI_TIMEOUT) do
        socket = TCPSocket.new(@config.host, @config.port.to_i)
        socket.gets # read AMI banner

        send_action(socket, 'Login', username: @config.username, secret: @config.password, events: 'off')
        login_resp = read_response(socket)
        raise "AMI Login failed: #{login_resp['message']}" unless login_resp['response'] == 'Success'

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
        socket.close

        { success: orig_resp['response'] == 'Success', message: orig_resp['message'] || orig_resp['response'] }
      end
    rescue Timeout::Error
      { success: false, message: 'Connection timeout' }
    rescue StandardError => e
      { success: false, message: e.message }
    end

    private

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
        break if line.nil? || line.empty?
        key, val = line.split(': ', 2)
        result[key.downcase] = val if key && val
      end
      result
    end
  end
end
