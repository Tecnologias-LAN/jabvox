# frozen_string_literal: true

require 'socket'
require 'timeout'

# Cliente AMI PROPIO del Voice Broadcast: origina las llamadas del agente virtual y
# comprueba conectividad, SIN depender del marcador (Jabvox::DialerService). Solo usa la
# config VoIP de la cuenta (host/puerto/usuario/secret + trunk/prefix/caller_id), que es
# el único requisito permitido para el módulo. Toda escritura AMI pasa por strip_crlf
# como defensa contra inyección CRLF.
class Jabvox::VoiceBroadcast::OriginateService
  AMI_TIMEOUT = 15
  CONNECT_TIMEOUT = 5

  def initialize(config)
    @config = config
  end

  # ¿El PBX (AMI) está accesible? Falla rápido ante un host caído.
  def ami_reachable?
    Timeout.timeout(CONNECT_TIMEOUT + 2) do
      with_ami_connection { |_socket| true }
    end
  rescue StandardError
    false
  end

  # Cuelga un canal en curso por su uniqueid (para detener de verdad una campaña: las
  # llamadas ya en vuelo dejan de sonar/reproducir en el PBX, no solo en BD). Best-effort.
  def hangup(uniqueid)
    return false if uniqueid.to_s.strip.empty?

    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        # AMI Hangup identificado por uniqueid del canal originado.
        send_action(socket, 'Hangup', uniqueid: uniqueid.to_s)
        read_response(socket)
      end
    end
    true
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] hangup #{uniqueid} failed | #{e.message}"
    false
  end

  # Origina una llamada hacia el contexto del agente virtual (dialer-voicebot), que
  # reproduce el audio a quien contesta. El dialplan de destino hace
  # Answer→[AMD]→Playback→[DTMF]→Hangup. Las variables __JABVOX_VB_* viajan heredables
  # para que el listener/handler correlacione los eventos con el destinatario.
  #
  # RUTEO DE SALIDA (clave): reutiliza el mismo contexto de marcación saliente que el
  # click-to-call/dialer del PBX (por defecto 'clicktocall'), NO un peer SIP directo.
  # Marca un canal `Local/<num>@<context>` que sale por el trunk que ese contexto ya
  # sabe usar; solo cae a `SIP/<num>@<trunk>` (o `SIP/<num>`) si se fuerza un trunk.
  # Así funciona con cualquier PBX que ya tenga su ruta saliente configurada.
  # Devuelve { success:, message:, actionid: }.
  def originate(phone:, broadcast:, recipient:, playback_ref:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    dial      = "#{provider_prefix}#{Jabvox::PhoneNormalizer.for_dialing(phone)}"
    channel   = outbound_channel(dial)
    action_id = "jabvoxvb-#{recipient.id}"
    result = { success: false, message: 'Connection error', actionid: action_id }
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        params = {
          channel: channel,
          context: 'dialer-voicebot',
          exten: 's',
          priority: 1,
          timeout: 30_000,
          async: 'true',
          actionid: action_id,
          variable: [
            "__JABVOX_BROADCAST_ID=#{broadcast.id}",
            "__JABVOX_VB_RECIPIENT_ID=#{recipient.id}",
            "__JABVOX_ACCOUNT_ID=#{broadcast.account_id}",
            "__JABVOX_VB_AUDIO=#{playback_ref}",
            "__JABVOX_VB_AMD=#{broadcast.amd_enabled_jabvox ? '1' : '0'}",
            "__JABVOX_VB_DTMF=#{broadcast.dtmf_enabled_jabvox ? '1' : '0'}",
            "__JABVOX_VB_OPTOUT=#{broadcast.dtmf_optout_digit_jabvox}"
          ]
        }
        cid = resolve_caller_id(broadcast.caller_id_jabvox.presence)
        params[:callerid] = cid if cid.present?
        Rails.logger.info "📡 [VoiceBroadcast] Originate | channel=#{channel} bcast=#{broadcast.id} recipient=#{recipient.id}"
        send_action(socket, 'Originate', **params)
        resp = read_response(socket)
        Rails.logger.info "📡 [VoiceBroadcast] AMI Response | response=#{resp['response']} message=#{resp['message']}"
        result = { success: resp['response'] == 'Success', message: resp['message'] || resp['response'], actionid: action_id }
      end
    end
    result
  rescue Timeout::Error
    { success: false, message: 'Connection timeout', actionid: action_id }
  rescue StandardError => e
    { success: false, message: e.message, actionid: action_id }
  end

  # Canal saliente hacia el número. Prioridad:
  #   1) Si hay dialer_trunk explícito → SIP/<num>@<trunk> (marcado directo al trunk).
  #   2) Si no → Local/<num>@<context> usando el context de salida del PBX
  #      (dialer_context o context, típicamente 'clicktocall'): deja que el dialplan
  #      del PBX elija el trunk y aplique su plan de marcación ya probado.
  # El "/n" del Local evita que Asterisk optimice/colapse el canal local antes de
  # tiempo, así los eventos y la reproducción llegan bien.
  def outbound_channel(dial)
    trunk = @config.dialer_trunk.presence
    return "SIP/#{dial}@#{trunk}" if trunk

    ctx = outbound_context
    return "Local/#{dial}@#{ctx}/n" if ctx.present?

    "SIP/#{dial}" # último recurso (PBX que registra el número como peer)
  end

  # Contexto de marcación saliente del PBX. Reutiliza el del click-to-call/dialer.
  def outbound_context
    (@config.respond_to?(:dialer_context) ? @config.dialer_context.presence : nil) ||
      (@config.respond_to?(:context) ? @config.context.presence : nil)
  end

  private

  # Abre socket AMI con connect-timeout duro (host caído falla en CONNECT_TIMEOUT s,
  # no en el default del SO ~75s). Implementación propia (no depende del marcador):
  # connect no bloqueante + wait_writable, que sí acota el tiempo total real.
  def connect_with_timeout(host, port, timeout)
    addr = Socket.sockaddr_in(port, host)
    socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    begin
      socket.connect_nonblock(addr)
    rescue IO::WaitWritable
      unless socket.wait_writable(timeout)
        socket.close
        raise Errno::ETIMEDOUT, "connect timed out after #{timeout}s to #{host}:#{port}"
      end
      begin
        socket.connect_nonblock(addr) # la segunda llamada confirma el resultado
      rescue Errno::EISCONN
        # Conectado — esperado en la segunda llamada.
      end
    end
    socket
  rescue StandardError
    socket&.close
    raise
  end

  def with_ami_connection
    socket = connect_with_timeout(@config.host, @config.port.to_i, CONNECT_TIMEOUT)
    read_line(socket) # consume el banner AMI ("Asterisk Call Manager/x.y.z")
    login_ami(socket)
    yield socket
  ensure
    socket&.close
  end

  def read_line(socket)
    line = socket.gets
    raise 'AMI connection closed by peer' if line.nil?

    line
  end

  def login_ami(socket)
    send_action(socket, 'Login', username: @config.username, secret: @config.password, events: 'off')
    login_resp = read_response(socket)
    raise "AMI Login failed: #{login_resp['message']}" unless login_resp['response'] == 'Success'
  end

  def provider_prefix
    @config.respond_to?(:dialer_provider_prefix) ? @config.dialer_provider_prefix.to_s.gsub(/\D/, '') : ''
  end

  # Caller ID del tramo saliente. Prioridad: caller_id de la campaña → dialer_caller_id
  # de la config VoIP → ninguno. Se reduce a dígitos (los proveedores rechazan "+",
  # espacios o rellenos). Nunca inventa un número falso (el trunk respondería 403).
  def resolve_caller_id(caller_id)
    raw = caller_id.presence || @config.dialer_caller_id.presence
    return nil if raw.blank?

    digits = raw.to_s.gsub(/\D/, '')
    digits.presence
  end

  def send_action(socket, action, **params)
    msg = "Action: #{strip_crlf(action)}\r\n"
    params.each do |key, val|
      k = strip_crlf(key)
      # AMI necesita UNA línea "Variable:" por variable; un Array emite líneas repetidas.
      if val.is_a?(Array)
        val.each { |v| msg += "#{k}: #{strip_crlf(v)}\r\n" }
      else
        msg += "#{k}: #{strip_crlf(val)}\r\n"
      end
    end
    msg += "\r\n"
    socket.write(msg)
  end

  # Defensa en profundidad contra inyección AMI/CRLF.
  def strip_crlf(value)
    value.to_s.delete("\r\n")
  end

  def read_response(socket)
    result = {}
    loop do
      raw = socket.gets
      break if raw.nil? # EOF — peer cerró la conexión

      line = raw.chomp
      break if line.empty? # línea en blanco termina el mensaje

      key, val = line.split(': ', 2)
      result[key.downcase] = val if key && val
    end
    result
  end
end
