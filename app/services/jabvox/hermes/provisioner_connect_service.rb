# frozen_string_literal: true

# Conecta (desde super admin) el Hermes APROVISIONADOR global ya existente: guarda su URL y
# token de servicio (cifrado) y verifica que responde. Ese Hermes ya sabe aprovisionar/crear
# más Hermes; Jabvox solo lo conecta y luego lo liga a cuentas.
#
# No expone el token; valida la conexión con un ping al endpoint del aprovisionador.
class Jabvox::Hermes::ProvisionerConnectService
  Result = Struct.new(:success, :provisioner, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(base_url:, service_token:)
    @base_url = base_url.to_s.strip
    @service_token = service_token.to_s.strip
  end

  def call
    return failure('La URL del aprovisionador es requerida.') if @base_url.blank?
    return failure('URL inválida.') unless valid_url?(@base_url)
    return failure('El token de servicio es requerido.') if @service_token.blank?

    ping = verify
    return failure(ping.error) unless ping.success?

    provisioner = JabvoxHermesProvisioner.instance
    provisioner.mark_connected!(base_url: @base_url, service_token: @service_token)
    Result.new(success: true, provisioner: provisioner)
  rescue StandardError => e
    JabvoxHermesProvisioner.instance.mark_error!(e.message)
    failure(e.message)
  end

  private

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Ping autenticado al aprovisionador (health). Nunca registra el token.
  # Hermes expone /health (liveness, público) y /v1/health (alias para clientes OpenAI).
  # Probamos ambas por si la URL se pega con o sin /v1. El health es público, pero mandamos
  # el bearer igual (Hermes lo ignora en health y lo exige en el resto).
  HEALTH_PATHS = %w[health v1/health].freeze

  def verify
    conn = Faraday.new(url: normalize(@base_url)) do |f|
      f.headers['Authorization'] = "Bearer #{@service_token}"
      f.options.open_timeout = 5
      f.options.timeout = 15
      f.adapter Faraday.default_adapter
    end
    last_status = nil
    HEALTH_PATHS.each do |path|
      resp = conn.get(path)
      return ok if resp.success?

      last_status = resp.status
    end
    failure("El aprovisionador respondió #{last_status} (health no disponible)")
  rescue Faraday::Error => e
    failure("No se pudo contactar al aprovisionador: #{e.class}")
  end

  def normalize(url)
    url.end_with?('/') ? url : "#{url}/"
  end

  def ok
    Result.new(success: true)
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
