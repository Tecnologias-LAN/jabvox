require 'net/http'
require 'uri'

module Jabvox
  class SmsSenderService
    def initialize(provider)
      @provider = provider
    end

    def send_sms(phone:, message:, account:, campaign: nil, contact: nil)
      sms_msg = account.jabvox_sms_messages.create!(
        jabvox_sms_provider: @provider,
        jabvox_sms_campaign: campaign,
        contact: contact,
        phone: sanitize_phone(phone),
        message: message,
        status: 'pending'
      )

      begin
        response = deliver(sanitize_phone(phone), message)
        if response.is_a?(Net::HTTPSuccess)
          sms_msg.update!(status: 'sent', external_id: response.body.strip.first(255), sent_at: Time.current)
          campaign&.increment!(:sent_count)
        else
          sms_msg.update!(status: 'failed', error_message: "HTTP #{response.code}: #{response.body.first(500)}")
          campaign&.increment!(:failed_count)
        end
      rescue StandardError => e
        sms_msg.update!(status: 'failed', error_message: e.message.first(500))
        campaign&.increment!(:failed_count)
      end

      sms_msg
    end

    def self.interpolate(template, contact)
      name_parts = contact.name.to_s.split(' ', 2)
      template
        .gsub(/\{nombre\}/i, name_parts[0].to_s)
        .gsub(/\{apellido\}/i, name_parts[1].to_s)
        .gsub(/\{telefono\}/i, contact.phone_number.to_s)
    end

    private

    def deliver(phone, message)
      base = @provider.base_url.to_s.chomp('/')
      uri = URI("#{base}/voziphone/index.php/sms/send")
      uri.query = URI.encode_www_form(
        username: @provider.api_user,
        password: @provider.api_password,
        number: phone,
        text: message
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 15
      http.read_timeout = 15
      http.get(uri.request_uri)
    end

    def sanitize_phone(phone)
      phone.to_s.gsub(/[+\s\-()]/, '')
    end
  end
end
