# frozen_string_literal: true

# Adaptador de infraestructura del Hermes Provisionador. Aísla CÓMO se aprovisiona una
# instancia Hermes (lo hace el Provisionador por su cuenta) del resto del código de Jabvox.
#
# - Http: habla con el endpoint del Hermes Provisionador (producción). Se le PIDE crear;
#   el Provisionador crea el contenedor si la cuenta no lo tiene. Jabvox no toca OVH/Docker.
# - Mock: para desarrollo/pruebas sin infraestructura viva. Simula el ciclo de vida.
#
# Contrato común (todas devuelven ProvisionerClient::Result):
#   create_or_get_instance(account_id:, identity:)
#   get_instance(account_id:)
#   disable_instance(account_id:)
#   restart_instance(account_id:)
#
# rubocop:disable Style/OneClassPerFile -- Http y Mock son las dos caras del mismo adaptador
module Jabvox::Hermes::InfraAdapter
  Result = Jabvox::Hermes::ProvisionerClient::Result

  # --- Producción: HTTP contra el Hermes Provisionador central ---
  class Http
    OPEN_TIMEOUT = 5
    TIMEOUT = 60 # crear una instancia puede tardar

    def initialize(base_url:, admin_key:)
      @base_url = base_url
      @admin_key = admin_key
    end

    def create_or_get_instance(account_id:, identity:)
      post('instances', account_id: account_id, identity: identity)
    end

    def get_instance(account_id:)
      get("instances/#{account_id}")
    end

    def disable_instance(account_id:)
      post("instances/#{account_id}/disable", {})
    end

    def restart_instance(account_id:)
      post("instances/#{account_id}/restart", {})
    end

    private

    def client
      @client ||= Faraday.new(url: normalize(@base_url)) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.headers['Authorization'] = "Bearer #{@admin_key}"
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def post(path, body)
      wrap { client.post(path) { |r| r.body = body } }
    end

    def get(path)
      wrap { client.get(path) }
    end

    def wrap
      resp = yield
      return Result.new(success: true, data: resp.body) if resp.success?

      Result.new(success: false, error: "Provisionador respondió #{resp.status}")
    rescue Faraday::Error => e
      Result.new(success: false, error: "No se pudo contactar al Provisionador: #{e.class}")
    end

    def normalize(url)
      url.end_with?('/') ? url : "#{url}/"
    end
  end

  # --- Dev/pruebas: simula el Provisionador sin infraestructura real ---
  class Mock
    def create_or_get_instance(account_id:, identity:)
      Result.new(success: true, data: {
                   'account_id' => account_id, 'identity' => identity,
                   'hermes_url' => "https://mock-hermes.local/account/#{account_id}",
                   'status' => 'ready', 'version' => 'mock-1.0', 'health' => 'ok'
                 })
    end

    def get_instance(account_id:)
      Result.new(success: true, data: { 'account_id' => account_id, 'status' => 'ready', 'health' => 'ok' })
    end

    def disable_instance(account_id:)
      Result.new(success: true, data: { 'account_id' => account_id, 'status' => 'disabled' })
    end

    def restart_instance(account_id:)
      Result.new(success: true, data: { 'account_id' => account_id, 'status' => 'ready' })
    end
  end
end
# rubocop:enable Style/OneClassPerFile
