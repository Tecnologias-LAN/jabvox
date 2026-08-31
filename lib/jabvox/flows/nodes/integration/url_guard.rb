# frozen_string_literal: true

# Guard anti-SSRF para los nodos `integration.*`, los ÚNICOS que salen a la red.
# Valida la URL antes de conectar: esquema, host bloqueado y rangos reservados.
module Jabvox::Flows::Nodes::Integration::UrlGuard
  module_function

  # Nombres que resuelven a la propia máquina o al servicio de metadatos cloud.
  BLOCKED_HOSTS = ['localhost', 'metadata.google.internal', 'metadata.goog',
                   'instance-data', 'metadata'].freeze

  # Rangos IPv4 reservados: privados, loopback, link-local (metadatos), CGNAT y 0/8.
  BLOCKED_IPV4 = ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
                  '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16'].freeze

  # Rangos IPv6 reservados: loopback, no especificada, ULA fc00::/7 y link-local fe80::/10.
  BLOCKED_IPV6 = ['::1/128', '::/128', 'fc00::/7', 'fe80::/10'].freeze

  RANGES = (BLOCKED_IPV4 + BLOCKED_IPV6).map { |cidr| IPAddr.new(cidr) }.freeze

  # Valida y devuelve la URI. Lanza ExecutionError con el motivo en español.
  def assert_safe_url!(raw_url)
    text = raw_url.to_s.strip
    reject!('la URL llegó vacía. Rellena el campo "URL" del paso.') if text.empty?

    uri = parse(text)
    scheme = uri.scheme.to_s.downcase
    reject!("el esquema \"#{scheme}\" no está permitido: usa http o https.") unless %w[http https].include?(scheme)

    host = uri.hostname.to_s.downcase
    reject!("la URL \"#{text}\" no tiene host.") if host.empty?
    reject!("el host \"#{host}\" está bloqueado por política SSRF.") if BLOCKED_HOSTS.include?(host)
    reject!("el host \"#{host}\" apunta a una IP reservada o interna (bloqueado por SSRF).") if blocked_ip?(host)

    uri
  end

  # ¿El host es una IP literal dentro de un rango reservado? Un nombre DNS no lo es.
  def blocked_ip?(host)
    # IPAddr normaliza la IPv4 mapeada en hex (`::ffff:7f00:1`) sin regex; `native`
    # saca la IPv4 embebida para compararla contra los rangos IPv4.
    ip = IPAddr.new(host)
    ip = ip.native if ip.ipv4_mapped?
    RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false
  end

  def parse(text)
    URI.parse(text)
  rescue URI::InvalidURIError
    reject!("la URL \"#{text}\" no es válida.")
  end

  def reject!(reason)
    raise Jabvox::Flows::Engine::ExecutionError,
          "No se pudo hacer la petición: #{reason}"
  end
end
