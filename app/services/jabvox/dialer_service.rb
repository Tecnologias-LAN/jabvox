require 'socket'
require 'timeout'

class Jabvox::DialerService
  AMI_TIMEOUT = 15
  # Tiempo (s) que la cola timbra a un miembro antes de rendirse. DEBE coincidir con
  # el timeout del Queue() en el dialplan (90s). Antes estaba en 30 y, siendo el más
  # corto, tumbaba al lead que YA había contestado si el agente tardaba >30s en que
  # su softphone auto-contestara (wrap-up, latencia). Configurable por campaña.
  DEFAULT_QUEUE_TIMEOUT = 90
  # Cap the TCP connect itself so a dead/unreachable PBX (e.g. an account whose
  # Asterisk is powered off) fails fast instead of hanging on the OS default
  # connect timeout (which can be minutes and would tie up the request/worker).
  CONNECT_TIMEOUT = 5

  # Opens a TCP socket with a hard, reliable connect timeout so an unreachable
  # host (e.g. an account whose PBX is powered off) fails in `timeout` seconds
  # instead of hanging on the OS default (~75s+). Uses a non-blocking connect +
  # wait_writable, which actually bounds the wait — Socket.tcp's connect_timeout
  # applies per resolved address and does not reliably cap total time when the
  # host silently drops SYNs. Shared by DialerService and AmiListenerService.
  def self.connect_with_timeout(host, port, timeout)
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
        socket.connect_nonblock(addr) # second call confirms the result
      rescue Errno::EISCONN
        # Connected — expected on the second call.
      end
    end
    socket
  rescue StandardError
    socket&.close
    raise
  end

  def initialize(config)
    @config = config
  end

  def originate_call(phone:, extension:, campaign:, contact:, account:, caller_id: nil, user_id: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    context = @config.dialer_context.presence || @config.context
    # Create the call log first so its id can ride on the channel (JABVOX_DIALER_LOG_ID),
    # letting the AMI Hangup handler record the uniqueid back onto this same row.
    call_log = create_call_log(contact, campaign, account, phone, user_id)
    result = { success: false, message: 'Connection error' }
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        params = build_originate_params(phone, extension, context, caller_id, campaign, contact, user_id, call_log.id)
        Rails.logger.info "📡 [Dialer] AMI Originate | host=#{@config.host}:#{@config.port} " \
                          "channel=#{params[:channel]} context=#{params[:context]} exten=#{params[:exten]} " \
                          "callerid=#{params[:callerid].inspect} vars=#{params[:variable]}"
        send_action(socket, 'Originate', **params)
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] AMI Response | response=#{resp['response']} message=#{resp['message']}"
        result = { success: resp['response'] == 'Success', message: resp['message'] || resp['response'] }
      end
    end
    finalize_call(contact, call_log, result[:success])
    result
  rescue Timeout::Error
    finalize_call(contact, call_log, false)
    { success: false, message: 'Connection timeout' }
  rescue StandardError => e
    finalize_call(contact, call_log, false)
    { success: false, message: e.message }
  end

  # VOICE BROADCAST — Origina una llamada hacia el contexto del agente virtual
  # (dialer-voicebot), que reproduce el audio a quien contesta. NO usa la Queue del
  # dialer predictivo: el destino es el trunk directo y el dialplan hace
  # Answer→[AMD]→Playback→[DTMF]→Hangup. Las variables __JABVOX_BROADCAST_* viajan
  # heredables para que el AMI listener correlacione los eventos con el destinatario.
  # Devuelve { success:, message:, actionid: }.
  def originate_voicebot(phone:, broadcast:, recipient:, playback_ref:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    dial    = "#{provider_prefix}#{Jabvox::PhoneNormalizer.for_dialing(phone)}"
    trunk   = @config.dialer_trunk.presence
    channel = trunk ? "SIP/#{dial}@#{trunk}" : "SIP/#{dial}"
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
        cid = resolve_caller_id(broadcast.caller_id_jabvox.presence, nil)
        params[:callerid] = cid if cid.present?
        Rails.logger.info "📡 [VoiceBroadcast] Originate | channel=#{channel} broadcast=#{broadcast.id} recipient=#{recipient.id}"
        send_action(socket, 'Originate', **params)
        resp = read_response(socket)
        result = { success: resp['response'] == 'Success', message: resp['message'] || resp['response'], actionid: action_id }
      end
    end
    result
  rescue Timeout::Error
    { success: false, message: 'Connection timeout', actionid: action_id }
  rescue StandardError => e
    { success: false, message: e.message, actionid: action_id }
  end

  # Creates or replaces the queue in queues_custom.conf and applies it with a
  # SELECTIVE reload (QueueReload, members preserved — never a full app_queue.so
  # reload, which would drop dynamic members of every queue).
  # Uses DelCat+NewCat so it is idempotent — safe to call on every campaign save.
  # wait_in_queue: true  → joinempty=yes / leavewhenempty=no  (leads wait in queue)
  # wait_in_queue: false → joinempty=no  / leavewhenempty=yes (leads hang up if no agent)
  def ensure_queue_exists(queue_name, wait_in_queue: true, queue_timeout: DEFAULT_QUEUE_TIMEOUT)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        resp = write_queue_config(socket, queue_name, wait_in_queue: wait_in_queue, queue_timeout: queue_timeout)
        Rails.logger.info "📡 [Dialer] Queue ensured | queue=#{queue_name} wait_in_queue=#{wait_in_queue} " \
                          "response=#{resp['response']} message=#{resp['message']}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] ensure_queue_exists failed | queue=#{queue_name} error=#{e.message}"
  end

  def add_to_queue(queue_name, extension)
    # Al conectar un agente SOLO se le añade como miembro; NO se reescribe la
    # config de la cola. Reescribirla (DelCat+NewCat+QueueReload) recreaba la cola
    # en caliente y tumbaba las llamadas que ya estaban en ella — justo cuando un
    # agente entraba al dialer con llamadas entrando. La provisión de la cola (con
    # el wait_in_queue correcto de la campaña) ocurre al guardar la campaña, no al
    # conectar. Solo la aseguramos si NO existe (p. ej. tras reinicio de Asterisk).
    ensure_queue_exists(queue_name) unless queue_exists?(queue_name)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueAdd',
                    queue: queue_name,
                    interface: "SIP/#{extension}",
                    penalty: 0,
                    paused: 'false')
        resp = read_response(socket)
        # "Already there" is not a failure: the agent is a member, which is the
        # desired end state. Log both cases without alarming on the benign one.
        Rails.logger.info "📡 [Dialer] QueueAdd | queue=#{queue_name} ext=#{extension} " \
                          "response=#{resp['response']} message=#{resp['message']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueueAdd failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  # ¿El AMI del PBX responde? Abre la conexión (con su login) y la cierra.
  # Sirve para saltar rápido las cuentas cuyo PBX está apagado/inalcanzable sin
  # recorrer colas. Devuelve false ante cualquier fallo de conexión/login.
  def ami_reachable?
    Timeout.timeout(CONNECT_TIMEOUT + 2) do
      with_ami_connection { |_socket| true }
    end
  rescue StandardError
    false
  end

  # ¿La cola ya está cargada en Asterisk? Se comprueba con QueueSummary (evento
  # QueueSummary por cada cola existente). Ante cualquier error asumimos que NO
  # existe, para que el flujo caiga en ensure_queue_exists y la cree — nunca
  # bloquea la conexión del agente.
  def queue_exists?(queue_name)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueSummary', queue: queue_name)
        return read_queue_summary(socket, queue_name)
      end
    end
    false
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] queue_exists? check failed, assuming absent | queue=#{queue_name} error=#{e.message}"
    false
  end

  # Lee la respuesta de QueueSummary: true si aparece un evento QueueSummary para
  # esta cola antes del QueueSummaryComplete (o del fin de mensajes).
  def read_queue_summary(socket, queue_name)
    20.times do
      resp = read_response(socket)
      return false if resp.empty? || resp['event']&.casecmp?('QueueSummaryComplete')
      return true if resp['event']&.casecmp?('QueueSummary') && resp['queue'] == queue_name
    end
    false
  end

  def remove_from_queue(queue_name, extension)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueRemove',
                    queue: queue_name,
                    interface: "SIP/#{extension}")
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueRemove | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueueRemove failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  # Miembros actuales de TODAS las colas dialer_camp_* en Asterisk, en una sola
  # pasada (QueueStatus). Devuelve { "dialer_camp_151" => ["1501","1502"], ... }
  # con las extensiones ya sin el prefijo SIP/. Usado por el job de reconciliación
  # para detectar agentes que quedaron en cola sin sesión activa.
  def dialer_queue_members
    result = Hash.new { |h, k| h[k] = [] }
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueStatus')
        # Cota de mensajes generosa (muchas colas × miembros) con corte por evento
        # de fin. No dependemos de un número exacto: paramos en QueueStatusComplete.
        2000.times do
          resp = read_response(socket)
          break if resp.empty? || resp['event']&.casecmp?('QueueStatusComplete')

          collect_queue_member(resp, result)
        end
      end
    end
    result
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] dialer_queue_members failed | #{e.message}"
    {}
  end

  # Añade a `result` la extensión de un evento QueueMember de una cola del dialer.
  def collect_queue_member(resp, result)
    return unless resp['event']&.casecmp?('QueueMember')

    queue = resp['queue'].to_s
    return unless queue.start_with?('dialer_camp_')

    loc = (resp['location'].presence || resp['name']).to_s
    ext = loc.sub(%r{\A(?:SIP|PJSIP)/}i, '')
    result[queue] << ext if ext.present?
  end

  def hangup_extension(extension)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        channel = find_active_channel(socket, extension)
        unless channel
          Rails.logger.warn "⚠️ [Dialer] hangup_extension: no active channel for SIP/#{extension}"
          return
        end
        send_action(socket, 'Hangup', channel: channel)
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] Hangup | channel=#{channel} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] hangup_extension failed | ext=#{extension} error=#{e.message}"
  end

  # ¿La extensión del agente tiene un canal ACTIVO en Asterisk ahora mismo? Se usa
  # ANTES de originar: si el agente sigue en una llamada (o su leg anterior aún no
  # se destruyó / está en wrap-up en el softphone), NO debemos marcar otro lead,
  # porque cuando ese lead conteste la cola no tendrá al agente disponible y se le
  # colgará con silencio (los "JOINEMPTY/LEAVEEMPTY"). Cierra la ventana de carrera
  # entre el Originate y el Answer del lead. Si el AMI no responde, devuelve false
  # (no bloquea la marcación: el pacing lo maneja el flujo 1:1 igualmente).
  def agent_busy_on_channel?(extension)
    return false if extension.blank?

    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        find_active_channel(socket, extension).present?
      end
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] agent_busy_on_channel? failed | ext=#{extension} error=#{e.message}"
    false
  end

  def prepare_agent_for_call(queue_name, extension)
    # Solo asegurar la cola si NO existe (p. ej. tras reinicio de Asterisk). Antes
    # se reescribía la config en CADA marcación, disparando un QueueReload que podía
    # tumbar llamadas en curso de esa cola. La config se provisiona al guardar la
    # campaña; aquí solo garantizamos que el agente sea miembro.
    ensure_queue_exists(queue_name) unless queue_exists?(queue_name)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueueAdd', queue: queue_name, interface: "SIP/#{extension}", penalty: 0, paused: 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueAdd (prepare) | queue=#{queue_name} ext=#{extension} " \
                          "response=#{resp['response']} message=#{resp['message']}"
        send_action(socket, 'QueuePause', queue: queue_name, interface: "SIP/#{extension}", paused: 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueueUnpause (prepare) | queue=#{queue_name} ext=#{extension} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] prepare_agent_for_call failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  def getvar(channel, variable)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'Getvar', channel: channel, variable: variable)
        resp = read_response(socket)
        return resp['value']
      end
    end
  rescue StandardError
    nil
  end

  def pause_in_queue(queue_name, extension, paused:)
    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        send_action(socket, 'QueuePause',
                    queue: queue_name,
                    interface: "SIP/#{extension}",
                    paused: paused ? 'true' : 'false')
        resp = read_response(socket)
        Rails.logger.info "📡 [Dialer] QueuePause | queue=#{queue_name} ext=#{extension} paused=#{paused} response=#{resp['response']}"
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] QueuePause failed | queue=#{queue_name} ext=#{extension} error=#{e.message}"
  end

  # P3 — Deja a una extensión FUERA de servicio del marcador de forma robusta, sin
  # depender de conocer la campaña. En UNA sola conexión AMI:
  #   1) QueuePause=true en TODAS las colas dialer_camp_* donde sea miembro (efecto
  #      inmediato: una pata pausada no recibe reparto aunque siga como miembro),
  #   2) QueueRemove de esas mismas colas (la saca del todo),
  #   3) Hangup del canal activo de esa extensión (corta una llamada ya en vuelo).
  # Quita SOLO la extensión indicada — nunca toca a otros agentes. Idempotente:
  # repetirlo no rompe nada (pausar/quitar algo ya ausente es no-op).
  def force_offline_extension(extension)
    return if extension.blank?

    Timeout.timeout(AMI_TIMEOUT) do
      with_ami_connection do |socket|
        queues = queues_with_member(socket, extension)
        queues.each do |q|
          send_action(socket, 'QueuePause', queue: q, interface: "SIP/#{extension}", paused: 'true')
          read_response(socket)
          send_action(socket, 'QueueRemove', queue: q, interface: "SIP/#{extension}")
          read_response(socket)
        end
        Rails.logger.info "📡 [Dialer] force_offline | ext=#{extension} colas=#{queues.inspect}"
        hangup_channel_on(socket, extension)
      end
    end
  rescue StandardError => e
    Rails.logger.error "❌ [Dialer] force_offline_extension failed | ext=#{extension} error=#{e.message}"
  end

  private

  # Colas dialer_camp_* donde la extensión figura como miembro (una pasada QueueStatus
  # sobre el socket ya abierto). Para no depender de conocer el campaign_id al salir.
  def queues_with_member(socket, extension)
    target = "SIP/#{extension}"
    found = []
    send_action(socket, 'QueueStatus')
    2000.times do
      resp = read_response(socket)
      break if resp.empty? || resp['event']&.casecmp?('QueueStatusComplete')

      q = queue_member_match(resp, target)
      found << q if q
    end
    found.uniq
  end

  # Nombre de la cola dialer_camp_* si este evento QueueMember es de `target`; si no, nil.
  def queue_member_match(resp, target)
    return nil unless resp['event']&.casecmp?('QueueMember')

    q = resp['queue'].to_s
    loc = (resp['location'].presence || resp['name']).to_s
    q.start_with?('dialer_camp_') && loc.casecmp?(target) ? q : nil
  end

  # Cuelga el canal activo de la extensión sobre un socket ya abierto (si lo hay).
  def hangup_channel_on(socket, extension)
    channel = find_active_channel(socket, extension)
    return if channel.blank?

    send_action(socket, 'Hangup', channel: channel)
    read_response(socket)
    Rails.logger.info "📡 [Dialer] force_offline hangup | channel=#{channel}"
  end

  def with_ami_connection
    socket = open_ami_socket
    read_line(socket) # consume the AMI banner ("Asterisk Call Manager/x.y.z")
    login_ami(socket)
    yield socket
  ensure
    socket&.close
  end

  # Opens the AMI TCP socket with a hard, reliable connect timeout so an
  # unreachable host (e.g. an account whose PBX is powered off) fails in
  # CONNECT_TIMEOUT seconds instead of hanging on the OS default (~75s+).
  # Uses a non-blocking connect + IO.select, which actually bounds the wait —
  # Socket.tcp's connect_timeout applies per resolved address and does not
  # reliably cap total time when the host silently drops SYNs.
  def open_ami_socket
    Jabvox::DialerService.connect_with_timeout(@config.host, @config.port.to_i, CONNECT_TIMEOUT)
  end

  # Reads a single line, treating a closed peer (nil) as an error so callers
  # don't silently proceed on a half-open socket.
  def read_line(socket)
    line = socket.gets
    raise 'AMI connection closed by peer' if line.nil?

    line
  end

  def login_ami(socket)
    send_action(socket, 'Login',
                username: @config.username,
                secret: @config.password,
                events: 'off')
    login_resp = read_response(socket)
    raise "AMI Login failed: #{login_resp['message']}" unless login_resp['response'] == 'Success'
  end

  # Writes queue config using UpdateConfig (no Command/queue show needed).
  # DelCat removes existing section (no-op if absent), NewCat creates fresh.
  # A selective QueueReload (Step 3) applies the change immediately.
  # Dialplan for this queue expects:
  #   [dialer-answered]
  #   exten => s,1,Answer()
  #    same => n,Set(CDR(dst)=${DIALER_PHONE})
  #    same => n,Set(CDR(src)=${CALLERID(num)})
  #    same => n,Queue(${DIALER_QUEUE},tb(dialer-autoanswer^s^1),,,90)
  #    same => n,Hangup()
  #   [dialer-autoanswer]
  #   exten => s,1,Set(SIPADDHEADER=Alert-Info: info=auto-answer)
  #    same => n,Return()
  def write_queue_config(socket, queue_name, wait_in_queue: true, queue_timeout: DEFAULT_QUEUE_TIMEOUT) # rubocop:disable Metrics/MethodLength
    joinempty      = wait_in_queue ? 'yes' : 'no'
    leavewhenempty = wait_in_queue ? 'no'  : 'yes'
    # Coincide con el timeout del Queue() en el dialplan; nunca menor (ver constante).
    q_timeout = queue_timeout.to_i.clamp(30, 300)

    # Step 1: try to delete existing category — ignore error if it doesn't exist yet
    socket.write("Action: UpdateConfig\r\n" \
                 "srcfilename: queues_custom.conf\r\n" \
                 "dstfilename: queues_custom.conf\r\n" \
                 "reload: no\r\n" \
                 "Action-000000: DelCat\r\n" \
                 "Cat-000000: #{queue_name}\r\n" \
                 "\r\n")
    read_response(socket)

    # Step 2: create category fresh with all required settings.
    # IMPORTANT: reload=no here. A full `reload: app_queue.so` recarga el módulo
    # de colas ENTERO y expulsa a los miembros dinámicos (QueueAdd) de TODAS las
    # colas — no solo de esta. Eso tumbaba a los agentes de las demás campañas
    # cada vez que se aseguraba una cola, y el marcador dejaba de llamar. Solo
    # escribimos el archivo aquí; el reload selectivo va en el Step 3.
    socket.write("Action: UpdateConfig\r\n" \
                 "srcfilename: queues_custom.conf\r\n" \
                 "dstfilename: queues_custom.conf\r\n" \
                 "reload: no\r\n" \
                 "Action-000000: NewCat\r\n" \
                 "Cat-000000: #{queue_name}\r\n" \
                 "Action-000001: Append\r\n" \
                 "Cat-000001: #{queue_name}\r\n" \
                 "Var-000001: strategy\r\n" \
                 "Value-000001: ringall\r\n" \
                 "Action-000002: Append\r\n" \
                 "Cat-000002: #{queue_name}\r\n" \
                 "Var-000002: timeout\r\n" \
                 "Value-000002: #{q_timeout}\r\n" \
                 "Action-000003: Append\r\n" \
                 "Cat-000003: #{queue_name}\r\n" \
                 "Var-000003: autopause\r\n" \
                 "Value-000003: no\r\n" \
                 "Action-000004: Append\r\n" \
                 "Cat-000004: #{queue_name}\r\n" \
                 "Var-000004: joinempty\r\n" \
                 "Value-000004: #{joinempty}\r\n" \
                 "Action-000005: Append\r\n" \
                 "Cat-000005: #{queue_name}\r\n" \
                 "Var-000005: leavewhenempty\r\n" \
                 "Value-000005: #{leavewhenempty}\r\n" \
                 "\r\n")
    read_response(socket)

    # Step 3: apply the config for THIS queue only, preserving members.
    # QueueReload with Members: no reloads the queue parameters from the config
    # file without touching dynamic members — so agents already added to other
    # queues (or this one) stay put.
    socket.write("Action: QueueReload\r\n" \
                 "Queue: #{queue_name}\r\n" \
                 "Members: no\r\n" \
                 "Rules: no\r\n" \
                 "Parameters: yes\r\n" \
                 "\r\n")
    read_response(socket)
  end

  def build_originate_params(phone, extension, context, caller_id, campaign, contact, user_id, call_log_id) # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
    # Dial with the country prefix but WITHOUT the leading "+" (see PhoneNormalizer):
    # Asterisk's dial plan expects bare digits, so "+573000000000" -> "573000000000".
    phone   = Jabvox::PhoneNormalizer.for_dialing(phone)
    # Provider/carrier prefix required by the trunk (e.g. "0000"), prepended right
    # before dialing. This is the operator prefix, NOT the country code — the
    # number already carries the country code (E.164).
    dial    = "#{provider_prefix}#{phone}"
    trunk   = @config.dialer_trunk.presence
    channel = trunk ? "SIP/#{dial}@#{trunk}" : "SIP/#{extension}"
    exten   = trunk ? 's' : dial
    queue   = "dialer_camp_#{campaign.id}"

    params = {
      channel: channel,
      context: context,
      exten: exten,
      priority: 1,
      timeout: 30_000,
      async: 'true',
      # ActionID que el OriginateResponse devuelve TAL CUAL. Lleva el call_log_id
      # embebido para que el listener cierre el log si el Originate FALLA de
      # inmediato (trunk congestionado / número inválido): en ese caso el canal
      # nunca se crea y leer JABVOX_DIALER_LOG_ID del canal da vacío, dejando el
      # log 'initiated' y al agente pegado en "Marcando…" hasta el reaper (~15min).
      actionid: "jabvoxdlog-#{call_log_id}",
      # `__` = variable HEREDABLE en Asterisk: se propaga a los canales hijos y
      # sobrevive al bridge, así el contexto dialer-answered puede hacer
      # Set(CDR(dst)=${DIALER_PHONE}) con el número real. Sin el `__`, DIALER_PHONE
      # llegaba vacía a ese punto y el CDR quedaba con dst='s'. Se lee como
      # ${DIALER_PHONE} (el `__` solo marca herencia al setear, no al leer).
      variable: ["__DIALER_QUEUE=#{queue}",
                 "__DIALER_PHONE=#{phone}",
                 "__JABVOX_CONTACT_ID=#{contact.id}",
                 "__JABVOX_ACCOUNT_ID=#{campaign.account_id}",
                 "__JABVOX_AGENT_USER_ID=#{user_id}",
                 "__JABVOX_DIALER_LOG_ID=#{call_log_id}",
                 "JABVOX_CAMPAIGN_ID=#{campaign.id}"]
    }
    cid = resolve_caller_id(caller_id, contact)
    params[:callerid] = cid if cid.present?
    params
  end

  # Digits-only provider prefix from the VoIP config (never the country code).
  def provider_prefix
    @config.respond_to?(:dialer_provider_prefix) ? @config.dialer_provider_prefix.to_s.gsub(/\D/, '') : ''
  end

  # Caller ID presented on the outbound trunk leg. Priority: explicit caller_id
  # (campaign) → the VoIP config's dialer_caller_id → none. The number is reduced
  # to bare digits (providers reject "+", spaces or a placeholder filler), and we
  # NEVER fall back to a fake number that trunks answer with 403 Forbidden.
  # Format: "Name <digits>" so the display name rides along when there is one.
  def resolve_caller_id(caller_id, contact)
    raw = caller_id.presence || @config.dialer_caller_id.presence
    return nil if raw.blank?

    digits = raw.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    # contact es nil en el voice broadcast (no hay ficha de lead en el CallerID).
    name = contact&.name_jabvox.to_s.gsub(/["<>]/, '').strip
    name.present? ? "\"#{name}\" <#{digits}>" : digits
  end

  def create_call_log(contact, campaign, account, phone, user_id = nil)
    account.jabvox_dialer_call_logs.create!(
      jabvox_dialer_campaign: campaign,
      jabvox_dialer_campaign_contact: contact,
      # Persist who dialed (the agent) so the report's "Agentes" column and the
      # per-call detail are correct in predictive mode too — previously this was
      # left NULL and every call fell into "sin agente".
      agent_id_jabvox: user_id,
      phone_jabvox: phone,
      status_jabvox: 'initiated',
      started_at_jabvox: Time.current
    )
  end

  def finalize_call(contact, call_log, success)
    # attempts_jabvox / last_attempt_at are bumped by the picker at reserve time
    # (single source of truth), so here we only set the status.
    contact.update!(status_jabvox: success ? 'calling' : 'failed')
    call_log.update!(status_jabvox: success ? 'initiated' : 'failed')
  end

  # Reads channel list from AMI Status and returns the exact channel name
  # for the given extension (e.g. "SIP/1010-00000abc").
  def find_active_channel(socket, extension)
    send_action(socket, 'Status')
    # Consume the initial "Channel status will follow" header
    read_response(socket)
    # Iterate Status events until StatusComplete or empty response
    100.times do
      event = read_response(socket)
      break if event.empty? || event['event']&.casecmp?('statuscomplete')
      next unless event['event']&.casecmp?('status')

      ch = event['channel'].to_s
      return ch if ch.start_with?("SIP/#{extension}-", "PJSIP/#{extension}-")
    end
    nil
  end

  def send_action(socket, action, **params)
    msg = "Action: #{strip_crlf(action)}\r\n"
    params.each do |key, val|
      k = strip_crlf(key)
      # AMI needs ONE "Variable:" line per channel variable; an Array emits
      # repeated lines. A comma-joined string would be read as a single var.
      if val.is_a?(Array)
        val.each { |v| msg += "#{k}: #{strip_crlf(v)}\r\n" }
      else
        msg += "#{k}: #{strip_crlf(val)}\r\n"
      end
    end
    msg += "\r\n"
    socket.write(msg)
  end

  # Defensa en profundidad contra inyección AMI/CRLF: ningún valor debe poder
  # incrustar saltos de línea que Asterisk interpretaría como acciones/claves
  # adicionales. Se aplica a TODA acción, no solo a las validadas aguas arriba.
  def strip_crlf(value)
    value.to_s.delete("\r\n")
  end

  # Reads one AMI message (up to the blank-line terminator) into a hash.
  # Returns {} on EOF (peer closed) instead of looping forever, so a dropped
  # connection surfaces as an empty/failed response rather than a hang.
  def read_response(socket)
    result = {}
    loop do
      raw = socket.gets
      break if raw.nil? # EOF — peer closed the connection

      line = raw.chomp
      break if line.empty? # blank line terminates the message

      key, val = line.split(': ', 2)
      result[key.downcase] = val if key && val
    end
    result
  end
end
