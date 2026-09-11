# frozen_string_literal: true

# Adaptador HTTP real hacia el proveedor de IA. Lee base_url y master key (cifrada) de la
# config singleton y firma cada request con Bearer. Devuelve un hash normalizado
# { status:, body:, body_text: } para que el Client decida reintentos/errores.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class HttpAdapter
      OPEN_TIMEOUT = 5
      TIMEOUT = 30

      def initialize(config)
        @config = config
      end

      def request(method, path, params: nil, body: nil)
        response = connection.public_send(method, path) do |req|
          req.params.update(params) if params.present?
          req.body = body if body.present?
        end
        { status: response.status, body: response.body, body_text: raw_text(response) }
      rescue Faraday::TimeoutError
        { status: 504, body: nil, body_text: 'timeout' }
      rescue Faraday::ConnectionFailed
        { status: 503, body: nil, body_text: 'connection_failed' }
      end

      private

      def connection
        url = @config.base_url_jabvox
        url = url.end_with?('/') ? url : "#{url}/"
        Faraday.new(url: url) do |f|
          f.request :json
          f.response :json, content_type: /\bjson$/
          f.headers['Authorization'] = "Bearer #{@config.master_key_jabvox}"
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = TIMEOUT
          f.adapter Faraday.default_adapter
        end
      end

      def raw_text(response)
        body = response.body
        body.is_a?(String) ? body : body.to_json
      rescue StandardError
        ''
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
