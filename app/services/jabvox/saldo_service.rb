module Jabvox
  class SaldoService
    DEFAULT_CURRENCY = 'COP'.freeze

    def initialize(config)
      @config = config
    end

    def fetch_balance
      return disconnected_response('No hay configuración de saldo activa') unless active_config?
      return disconnected_response('URL del proxy no configurada') if config.proxy_url_jabvox.blank?

      response = HTTParty.get(
        config.proxy_url_jabvox,
        query: {
          key: config.api_key_jabvox,
          secret: config.api_secret_jabvox
        },
        timeout: 8
      )

      body = parsed_body(response.body)
      return disconnected_response('Respuesta inválida del proxy') unless body.is_a?(Hash)

      connected = body['success'] == true
      return disconnected_response(body['message'] || body['msg'] || body['error'] || 'Conexión fallida') unless connected

      balance = parse_balance(body)
      result = {
        connected: true,
        balance: balance,
        currency: DEFAULT_CURRENCY,
        message: 'Conexión activa'
      }

      persist_cache(result)
      result
    rescue StandardError => e
      disconnected_response(e.message)
    end

    private

    attr_reader :config

    def active_config?
      config.present? && config.is_active_jabvox?
    end

    def parsed_body(body)
      return body if body.is_a?(Hash)

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def parse_balance(body)
      return body.to_f if body.is_a?(Numeric)
      return body.to_f if body.is_a?(String) && body.match?(/\A\d+(\.\d+)?\z/)

      candidate = body['balance'] || body['credit'] || body.dig('rows', 0, 'credit')
      candidate.to_f
    end

    def persist_cache(response)
      config.update_columns(
        cached_balance_jabvox: response[:balance],
        balance_updated_at_jabvox: Time.current,
        updated_at: Time.current
      )
    end

    def disconnected_response(message)
      {
        connected: false,
        balance: config&.cached_balance_jabvox.to_f,
        currency: DEFAULT_CURRENCY,
        message: message
      }
    end
  end
end
