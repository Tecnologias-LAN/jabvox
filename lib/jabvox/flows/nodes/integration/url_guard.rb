# frozen_string_literal: true

# Guard anti-SSRF para los nodos `integration.*`, los ÚNICOS que salen a la red.
# Valida la URL antes de conectar: esquema, host bloqueado y rangos reservados.
#
# RESOLUCIÓN PINNEADA (anti DNS-rebinding): no basta validar el NOMBRE y luego dejar
# que `Net::HTTP` vuelva a resolver el DNS al conectar — entre validación y conexión
# el DNS puede cambiar a una IP interna (TOCTOU). Por eso `resolved_endpoint!`
# resuelve el host UNA vez, valida TODAS sus IPs y devuelve la IP concreta a la que
# conectar; el que llama abre la conexión contra esa IP, conservando el Host y el SNI.
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

  # Cuánto se espera por la resolución DNS: un host que no resuelve rápido se trata
  # como "no responde" en vez de colgar el worker.
  RESOLVE_TIMEOUT_S = 5

  # Valida y devuelve la URI. Lanza ExecutionError con el motivo en español.
  def assert_safe_url!(raw_url)
    uri, = resolved_endpoint!(raw_url)
    uri
  end

  # Valida la URL y RESUELVE el host para comprobar que NINGUNA de sus IPs es
  # interna (defensa anti DNS-rebinding: un nombre público que apunta a una IP
  # privada se rechaza aquí). Devuelve [uri, ip_string|nil].
  #
  # Si la resolución falla (host inexistente, sin DNS en el entorno), NO se rechaza
  # aquí: se deja que la conexión real lo reporte con "No se pudo conectar". Así el
  # usuario recibe igual el error de un dominio que no responde, y el guard no
  # depende de un resolvedor disponible para dejar pasar a un host público legítimo.
  def resolved_endpoint!(raw_url)
    uri = validated_uri!(raw_url)
    host = uri.hostname.to_s.downcase

    # Un host que YA es una IP literal no se resuelve: se valida y se usa tal cual.
    return [uri, host] if literal_ip?(host)

    ips = resolve(host)
    ips.each do |ip|
      reject!("el host \"#{host}\" resuelve a una IP reservada o interna (bloqueado por SSRF).") if blocked_ip?(ip)
    end
    [uri, ips.first]
  end

  # Solo esquema, host presente y no en la lista negra de nombres. La validación
  # de IP se hace en `resolved_endpoint!` (tras resolver), no aquí.
  def validated_uri!(raw_url)
    text = raw_url.to_s.strip
    reject!('la URL llegó vacía. Rellena el campo "URL" del paso.') if text.empty?

    uri = parse(text)
    scheme = uri.scheme.to_s.downcase
    reject!("el esquema \"#{scheme}\" no está permitido: usa http o https.") unless %w[http https].include?(scheme)

    host = uri.hostname.to_s.downcase
    reject!("la URL \"#{text}\" no tiene host.") if host.empty?
    reject!("el host \"#{host}\" está bloqueado por política SSRF.") if BLOCKED_HOSTS.include?(host)
    reject!("el host \"#{host}\" apunta a una IP reservada o interna (bloqueado por SSRF).") if literal_ip?(host) && blocked_ip?(host)

    uri
  end

  # Resuelve un nombre a sus IPs (v4 y v6), acotado en tiempo. Devuelve [] si no
  # resuelve: la capa de conexión reportará "No se pudo conectar". La resolución
  # sirve para VALIDAR las IPs (anti-rebinding), no para decidir existencia.
  def resolve(host)
    Timeout.timeout(RESOLVE_TIMEOUT_S) do
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    end
  rescue Timeout::Error, SocketError
    []
  end

  def literal_ip?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false
  end

  # ¿La IP está dentro de un rango reservado?
  def blocked_ip?(ip_string)
    # IPAddr normaliza la IPv4 mapeada en hex (`::ffff:7f00:1`) sin regex; `native`
    # saca la IPv4 embebida para compararla contra los rangos IPv4.
    ip = IPAddr.new(ip_string)
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
