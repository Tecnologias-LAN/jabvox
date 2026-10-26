require 'resolv'
require 'ipaddr'

# SSRF protection for external database connections. Resolves a hostname to ALL of its
# IPs and rejects any that fall in private / loopback / link-local / metadata ranges,
# unless an administrator explicitly allowed private networks on the data source.
#
# Cloud metadata (169.254.169.254) is ALWAYS blocked, even with the override.
#
#   result = Jabvox::Analytics::HostGuardService.new(
#     host: 'db.example.com', port: 5432, allow_private: false
#   ).call
#   result.allowed? #=> true/false ; result.reason ; result.resolved_ips
class Jabvox::Analytics::HostGuardService
  Result = Struct.new(:allowed, :reason, :resolved_ips, keyword_init: true) do
    def allowed?
      allowed
    end
  end

  # Always-blocked addresses regardless of the allow_private override.
  HARD_BLOCKED = ['169.254.169.254', 'fd00:ec2::254'].freeze

  # Ranges blocked unless allow_private is set.
  PRIVATE_RANGES = [
    '127.0.0.0/8', '::1/128',          # loopback
    '0.0.0.0/8', '::/128',             # unspecified
    '169.254.0.0/16', 'fe80::/10',     # link-local
    '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', # RFC1918
    'fc00::/7',                        # IPv6 ULA
    '100.64.0.0/10'                    # CGNAT
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  DEFAULT_ALLOWED_PORTS = [5432, 3306, 5433, 3307, 1433].freeze

  # Sentinel para "cualquier puerto válido 1-65535". Lo pasan los webhooks
  # salientes, que deben poder apuntar a cualquier puerto del endpoint del cliente.
  ANY_PORT = :any

  # Reglas de puerto:
  #  - allowed_ports == ANY_PORT  -> cualquier puerto 1-65535 (webhooks salientes).
  #  - allowed_ports lista        -> el puerto debe estar en la lista, O ser un
  #    puerto no privilegiado (1024-65535). Esto cubre las BD externas de Analytics,
  #    que escuchan en puertos variados.
  # El puerto NO es la defensa anti-SSRF: esa es el bloqueo de IPs privadas/metadata
  # (PRIVATE_RANGES / HARD_BLOCKED), que sigue vigente en #call pase lo que pase aquí.
  # Antes esta comprobación ignoraba @allowed_ports y rechazaba 443/80 (puertos
  # privilegiados), bloqueando TODO webhook HTTP/HTTPS.
  def port_allowed?
    port = @port.to_i
    return port.between?(1, 65_535) if @allowed_ports == ANY_PORT

    @allowed_ports.map(&:to_i).include?(port) || port.between?(1024, 65_535)
  end

  def initialize(host:, port: nil, allow_private: false, allowed_ports: DEFAULT_ALLOWED_PORTS)
    @host = host.to_s.strip
    @port = port
    @allow_private = allow_private
    @allowed_ports = allowed_ports
  end

  def call
    return deny('Host vacío') if @host.blank?
    return deny("Puerto #{@port} no permitido") if @port.present? && !port_allowed?

    ips = resolve
    return deny('No se pudo resolver el host') if ips.empty?

    reason = blocked_reason(ips)
    return deny(reason) if reason

    Result.new(allowed: true, reason: 'ok', resolved_ips: ips)
  rescue IPAddr::Error => e
    deny("IP inválida: #{e.message}")
  end

  private

  # Returns the block reason for the first offending IP, or nil if all are allowed.
  def blocked_reason(ips)
    ips.each do |ip|
      addr = IPAddr.new(ip)
      return "Dirección bloqueada (metadata): #{ip}" if hard_blocked?(addr)
      return "Dirección de red interna bloqueada: #{ip}" if !@allow_private && private?(addr)
    end
    nil
  end

  def resolve
    # If the host is already a literal IP, use it directly; otherwise resolve A/AAAA.
    IPAddr.new(@host)
    [@host]
  rescue IPAddr::Error
    Resolv::DNS.open do |dns|
      a = dns.getresources(@host, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s }
      aaaa = dns.getresources(@host, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s }
      (a + aaaa).uniq
    end
  rescue StandardError
    []
  end

  def hard_blocked?(addr)
    HARD_BLOCKED.any? do |blocked|
      addr == IPAddr.new(blocked)
    rescue IPAddr::Error
      false
    end
  end

  def private?(addr)
    PRIVATE_RANGES.any? { |range| range.include?(addr) }
  end

  def deny(reason)
    Result.new(allowed: false, reason: reason, resolved_ips: [])
  end
end
