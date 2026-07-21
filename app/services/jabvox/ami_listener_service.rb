require 'socket'

module Jabvox
  class AmiListenerService # rubocop:disable Metrics/ClassLength
    RECONNECT_DELAY = 10
    READ_TIMEOUT    = 35
    # Bound the TCP connect so an account whose PBX is powered off (unreachable
    # host) fails in seconds instead of blocking ~75s on the OS default connect
    # timeout. Without this, each dead account's listener thread stalls on
    # connect before it can even log the failure and back off.
    CONNECT_TIMEOUT = 5

    # Hard cap on cached call markers. Each active call adds a few keys (channel,
    # uniqueid, linkedid); when a Hangup is missed, its keys would leak forever, so
    # we evict the oldest once the cache exceeds this size. Far above any real
    # concurrent-call count, so live calls are never evicted prematurely.
    MAX_CACHED_KEYS = 5000

    def initialize(account_id)
      @account_id      = account_id
      @active_channels = {}
      @channel_vars    = {} # correlation_id (channel/uniqueid/linkedid) => { 'CTCALL_ID' => '…' }
      @call_keys       = {} # linkedid => [all correlation ids of that call] — for full cleanup
      @answered_logs   = {} # dialer_call_log_id => true — call_assigned ya emitido (idempotencia)
      @socket          = nil
    end

    def run
      loop do
        run_once
      rescue StandardError => e
        Rails.logger.error "❌ [AmiListener] account=#{@account_id} reconnecting in #{RECONNECT_DELAY}s | #{e.message}"
        sleep RECONNECT_DELAY
      end
    end

    private

    def run_once
      config = Account.find(@account_id).jabvox_voip_config
      raise 'No VoIP config' unless config&.host.present?

      @config = config
      @socket = Jabvox::DialerService.connect_with_timeout(config.host, config.port.to_i, CONNECT_TIMEOUT)
      # Banner con timeout: un PBX que acepta TCP pero nunca envía banner colgaba
      # el thread aquí para siempre (connect_with_timeout solo cubre el TCP).
      raise 'AMI banner timeout' unless IO.select([@socket], nil, nil, CONNECT_TIMEOUT)

      @socket.gets # banner
      login(@socket, config)
      Rails.logger.info "✅ [AmiListener] account=#{@account_id} connected to #{config.host}"
      listen
    ensure
      begin
        @socket&.close
      rescue StandardError
        nil
      end
      @socket = nil
    end

    def login(socket, config)
      socket.write("Action: Login\r\nUsername: #{config.username}\r\nSecret: #{config.password}\r\nEvents: on\r\n\r\n")
      resp = read_response(socket)
      raise "AMI Login failed: #{resp['message']}" unless resp['response'] == 'Success'
    end

    def listen
      loop do
        ready = IO.select([@socket], nil, nil, READ_TIMEOUT)
        unless ready
          send_ping
          next
        end
        event = read_response(@socket)
        next if event.empty?

        dispatch_event(event)
      end
    end

    # Ping keep-alive con ActionID: consumimos su Pong explícitamente (casando por
    # id, despachando cualquier evento que llegue antes) para que la respuesta del
    # Ping no la "robe" un Getvar posterior — bug que dejaba el marcador en nil y
    # activaba heurísticas de correlación equivocadas.
    def send_ping
      action_id = next_action_id
      send_action(@socket, 'Ping', actionid: action_id)
      await_response(action_id)
    rescue StandardError => e
      Rails.logger.warn "⚠️ [AmiListener] ping failed | #{e.message}"
      raise # que el loop de run reconecte si el socket está roto
    end

    # ActionID único por acción (monótono; evita Math.random/Date que están
    # bloqueados y romperían el resume). Sirve para casar respuesta⇄acción.
    def next_action_id
      @action_seq = (@action_seq || 0) + 1
      "jbx-#{@account_id}-#{@action_seq}"
    end

    # Lee del socket hasta encontrar la RESPUESTA con este ActionID, despachando
    # por el camino cualquier EVENTO que llegue (nunca se pierde un evento). Tras
    # un número acotado de mensajes intermedios, se rinde y devuelve {} para no
    # bloquear el listener indefinidamente.
    def await_response(action_id, max_messages: 40)
      max_messages.times do
        msg = read_response(@socket)
        return msg if msg['actionid'] == action_id
        # Respuesta sin actionid (AMI viejo) tras nuestra acción: la tomamos.
        return msg if msg.key?('response') && !msg.key?('actionid') && !msg.key?('event')

        dispatch_event(msg) if msg.key?('event')
      end
      {}
    end

    def dispatch_event(event)
      evt_name = event['event'].to_s
      Rails.logger.debug { "🔎 [AmiListener] event=#{evt_name}" } if evt_name.present?

      case evt_name.downcase
      when 'varset'
        handle_varset(event)
      when 'agentconnect'
        handle_agent_connect(event)
      when 'agentcomplete'
        handle_agent_complete(event)
      when 'newstate'
        handle_newstate(event)
      when 'bridgeenter'
        handle_bridge_enter(event)
      when 'hangup'
        handle_hangup(event)
      when 'originateresponse'
        handle_originate_response(event)
      end
    end

    # En modo one_by_one NO hay cola Asterisk, así que AgentConnect nunca llega y
    # broadcast_call_assigned no se disparaba: el agente se quedaba pegado en
    # "Llamando…" aunque el cliente contestara. Newstate con estado "Up" (6) es
    # el evento que marca "la llamada fue contestada" en un Originate directo.
    # Resolvemos la llamada por el JABVOX_DIALER_LOG_ID que viaja en el canal
    # (o por la campaña activa como respaldo) y avisamos al frontend UNA vez.
    def handle_newstate(event)
      return unless event['channelstatedesc'].to_s.casecmp?('Up') ||
                    event['channelstate'].to_s == '6'

      notify_dialer_answered_from_channel(event['channel'].to_s, event)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_newstate failed | #{e.message}"
    end

    # BridgeEnter es el respaldo: cuando los dos legs (agente + cliente) se unen,
    # la llamada está conectada. Cubre dialplans donde el Newstate 'Up' llega en
    # un leg sin el marcador.
    def handle_bridge_enter(event)
      notify_dialer_answered_from_channel(event['channel'].to_s, event)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_bridge_enter failed | #{e.message}"
    end

    # Dispara call_assigned una sola vez por llamada del dialer a partir del canal
    # que se acaba de contestar/puentear. Idempotente vía @answered_logs.
    def handle_dialer_answered(channel, event)
      return if channel.blank?

      log_id = channel_var(channel, 'JABVOX_DIALER_LOG_ID', event)
      log = log_id.present? ? JabvoxDialerCallLog.find_by(id: log_id.to_i, account_id: @account_id) : nil
      # Respaldo: sin marcador en el canal, usar la llamada 'calling' más reciente.
      # Solo si el canal pertenece a ESTA cuenta o al trunk del dialer configurado;
      # de lo contrario un Newstate/BridgeEnter de un canal ajeno (entrante, otra
      # cuenta en PBX compartido) marcaba como "contestada" una llamada que aún
      # sonaba, mostrando al agente "conectado" con un cliente que no respondió.
      log ||= recover_open_dialer_log(channel, event)
      return unless log&.jabvox_dialer_campaign_contact_id && log.agent_id_jabvox

      @answered_logs ||= {}
      return if @answered_logs[log.id] # ya avisado

      @answered_logs[log.id] = true
      evict_answered_logs_if_needed
      broadcast_call_assigned(log.agent_id_jabvox, log.jabvox_dialer_campaign_contact_id, log.jabvox_dialer_campaign_id)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_dialer_answered failed | #{e.message}"
    end
    alias notify_dialer_answered_from_channel handle_dialer_answered

    # La llamada abierta ('initiated'/'calling') más reciente cuyo canal del trunk
    # coincide — usada cuando el Newstate/BridgeEnter no trae el marcador. Solo se
    # usa si hay UNA sola llamada abierta reciente, para no asignar la equivocada
    # cuando varias campañas marcan a la vez.
    def recover_open_dialer_log(channel, event = nil)
      return nil unless channel.to_s.start_with?('SIP/', 'PJSIP/', 'Local/')
      # El canal debe ser de esta cuenta (marcador) o del trunk del dialer: si no,
      # es un canal ajeno y NO debe correlacionarse con una llamada del dialer.
      return nil unless channel_belongs_to_dialer?(channel, event)

      open = JabvoxDialerCallLog
             .where(account_id: @account_id, status_jabvox: %w[initiated calling])
             .where('started_at_jabvox > ?', 2.minutes.ago)
             .order(started_at_jabvox: :desc).limit(2).to_a
      open.size == 1 ? open.first : nil
    rescue StandardError
      nil
    end

    # ¿El canal es atribuible al dialer de esta cuenta? True si lleva el marcador
    # JABVOX_ACCOUNT_ID de esta cuenta, o si el nombre del canal usa el trunk del
    # dialer configurado (SIP/<trunk>-… o SIP/<trunk>/…). Sin marcador ni match de
    # trunk configurado, devolvemos false para no correlacionar canales ajenos.
    def channel_belongs_to_dialer?(channel, event = nil)
      marker = channel_var(channel, 'JABVOX_ACCOUNT_ID', event)
      return marker.to_s == @account_id.to_s if marker.present?

      trunk = @config&.dialer_trunk.to_s
      return false if trunk.blank?

      ch = channel.to_s
      ch.start_with?("SIP/#{trunk}-", "SIP/#{trunk}/", "PJSIP/#{trunk}-", "PJSIP/#{trunk}/")
    rescue StandardError
      false
    end

    def evict_answered_logs_if_needed
      return if @answered_logs.size <= MAX_CACHED_KEYS

      @answered_logs.keys.first(@answered_logs.size - (MAX_CACHED_KEYS / 2)).each { |k| @answered_logs.delete(k) }
    end

    # Cache the click-to-call / dialer markers as soon as Asterisk sets them
    # (VarSet fires at call start). Reading them with Getvar at Hangup time is
    # unreliable — the channel is already being destroyed and returns blank,
    # so the typify dialog never opened. Keyed by channel; cleared on Hangup.
    TRACKED_VARS = %w[
      CTCALL_ID CTCALL_ACCOUNT
      JABVOX_DIALER_LOG_ID JABVOX_ACCOUNT_ID JABVOX_CONTACT_ID JABVOX_AGENT_USER_ID
    ].freeze
    def handle_varset(event)
      channel = event['channel'].to_s
      # Inheritable channel vars are set as "__CTCALL_ID" / "__JABVOX_…" (double
      # underscore), and Asterisk reports that exact name in VarSet. Strip the
      # leading underscores so it matches TRACKED_VARS and the later lookups.
      var = event['variable'].to_s.sub(/\A_+/, '')
      return if channel.blank? || TRACKED_VARS.exclude?(var)

      value = event['value'].to_s
      # Cache under EVERY correlation id of the call, not just the channel name.
      # A click-to-call has two legs (agent SIP/ext and the customer trunk leg);
      # the inheritable var rides along, but the Hangup can come from either leg.
      # Uniqueid/Linkedid group all legs of the same call, so caching by them lets
      # the Hangup find the marker no matter which leg hung up (agent, customer or
      # the in-app button).
      keys = [channel, event['uniqueid'], event['linkedid']].map(&:to_s).reject(&:blank?).uniq
      keys.each { |key| (@channel_vars[key] ||= {})[var] = value }

      # Index every key under the call's linkedid so ONE Hangup clears them all,
      # even when the hung-up leg has a different channel/uniqueid than the leg
      # that carried the VarSet. Without this, the other leg's keys would leak.
      group = event['linkedid'].to_s
      group = channel if group.blank?
      (@call_keys[group] ||= []).concat(keys)
      @call_keys[group].uniq!

      evict_cache_if_needed
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_varset failed | #{e.message}"
    end

    # Removes every cached key belonging to a call, by its linkedid (or channel
    # as fallback). Called on Hangup so no leg's markers are left behind.
    def clear_call_cache(linkedid, channel)
      group = linkedid.to_s.presence || channel.to_s
      (@call_keys.delete(group) || []).each { |k| @channel_vars.delete(k) }
      # Also drop the hung-up leg's own ids in case they were never grouped.
      [channel, linkedid].map(&:to_s).reject(&:blank?).each { |k| @channel_vars.delete(k) }
    end

    # Backstop against leaks: if a call's Hangup is never seen (dropped event,
    # reconnect mid-call), its keys would stay forever. Once the cache grows past
    # the cap, drop the oldest half — Ruby preserves insertion order, so the first
    # keys are the oldest calls, already long over.
    def evict_cache_if_needed
      return if @channel_vars.size <= MAX_CACHED_KEYS

      @channel_vars.keys.first(@channel_vars.size - (MAX_CACHED_KEYS / 2)).each { |k| @channel_vars.delete(k) }
      @call_keys.keys.first([@call_keys.size - (MAX_CACHED_KEYS / 2), 0].max).each { |k| @call_keys.delete(k) }
    end

    # @active_channels crecía sin límite: cada Hangup/AgentComplete perdido dejaba
    # su entrada para siempre (memory leak en dialers de alto volumen que corren
    # semanas). Al superar el cap, descarta las entradas más viejas (Ruby preserva
    # orden de inserción); están muy por encima de cualquier concurrencia real, así
    # que nunca desaloja llamadas vivas.
    def evict_active_channels_if_needed
      return if @active_channels.size <= MAX_CACHED_KEYS

      @active_channels.keys.first(@active_channels.size - (MAX_CACHED_KEYS / 2)).each { |k| @active_channels.delete(k) }
    end

    # Returns a cached marker for any of the call's correlation ids (channel name,
    # uniqueid or linkedid), falling back to a live Getvar on the channel only if
    # nothing was cached (older channels / missed VarSet).
    def channel_var(channel, variable, event = nil)
      keys = [channel]
      keys += [event['uniqueid'], event['linkedid']] if event
      keys.each do |key|
        cached = @channel_vars.dig(key.to_s, variable)
        return cached if cached.present?
      end
      getvar_on_existing(channel, variable)
    end

    def handle_agent_connect(event) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      queue = event['queue'].to_s
      return unless queue.start_with?('dialer_camp_')

      caller_channel = event['channel'].to_s
      dest_channel   = event['destchannel'].to_s
      # Issabel sends member interface as 'interface'; upstream Asterisk uses 'member'
      member    = event['interface'].presence || event['member'].to_s
      extension = strip_sip_prefix(member)
      return if caller_channel.blank? || extension.blank?

      contact_id = channel_var(caller_channel, 'JABVOX_CONTACT_ID', event)
      contact_id ||= channel_var(dest_channel, 'JABVOX_CONTACT_ID') if dest_channel.present?
      user_id_s  = channel_var(caller_channel, 'JABVOX_AGENT_USER_ID', event)
      user_id_s  ||= channel_var(dest_channel, 'JABVOX_AGENT_USER_ID') if dest_channel.present?

      campaign_id = parse_campaign_id(queue)
      # Fallback: some dialplans dial the trunk from a context, so the __JABVOX_*
      # markers never reach the leg AMI reports. Recover contact + agent from the
      # most recent 'calling' campaign-contact of this queue's campaign and its
      # dialer call log, so AgentConnect still shows the lead and marks it answered.
      if contact_id.blank? || user_id_s.blank?
        recovered = recover_dialer_call(campaign_id, extension)
        contact_id ||= recovered[:contact_id]
        user_id_s  ||= recovered[:user_id]
      end

      Rails.logger.info "🔍 [AmiListener] AgentConnect | contact_id=#{contact_id.inspect} user_id=#{user_id_s.inspect} channel=#{caller_channel}"

      return unless contact_id.present? && user_id_s.present?

      contact_id  = contact_id.to_i
      user_id     = user_id_s.to_i

      Rails.logger.info "📞 [AmiListener] AgentConnect | account=#{@account_id} ext=#{extension} queue=#{queue} user=#{user_id}"

      info = { contact_id: contact_id, user_id: user_id, campaign_id: campaign_id,
               extension: extension, caller_channel: caller_channel, dest_channel: dest_channel }
      @active_channels[caller_channel] = info
      @active_channels[dest_channel]   = info if dest_channel.present?
      evict_active_channels_if_needed

      # Persist that the lead was reached + who took it, so the campaign report
      # shows it as answered with the agent even if no later event correlates.
      mark_dialer_answered(campaign_id, contact_id, user_id)

      broadcast_call_assigned(user_id, contact_id, campaign_id)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_agent_connect failed | #{e.message}"
    end

    # Best-effort recovery of the lead+agent currently being dialed on a campaign
    # when the channel markers aren't present. Uses the newest 'calling'
    # campaign-contact and its call log's agent.
    def recover_dialer_call(campaign_id, _extension)
      return {} if campaign_id.blank?

      cc = JabvoxDialerCampaignContact
           .where(account_id: @account_id, jabvox_dialer_campaign_id: campaign_id, status_jabvox: 'calling')
           .order(last_attempt_at_jabvox: :desc).first
      return {} unless cc

      log = JabvoxDialerCallLog.where(jabvox_dialer_campaign_contact_id: cc.id).order(started_at_jabvox: :desc).first
      { contact_id: cc.contact_id, user_id: log&.agent_id_jabvox }
    rescue StandardError
      {}
    end

    # Marks the dialed campaign-contact as answered and its latest call log as
    # answered + agent, so the report counts it correctly.
    def mark_dialer_answered(campaign_id, contact_id, user_id)
      return if campaign_id.blank? || contact_id.blank?

      cc = JabvoxDialerCampaignContact.find_by(account_id: @account_id, jabvox_dialer_campaign_id: campaign_id, contact_id: contact_id)
      return unless cc

      cc.update_columns(status_jabvox: 'completed') if cc.status_jabvox == 'calling' # rubocop:disable Rails/SkipsModelValidations
      log = JabvoxDialerCallLog.where(jabvox_dialer_campaign_contact_id: cc.id).order(started_at_jabvox: :desc).first
      return unless log

      attrs = { status_jabvox: 'answered', lead_answered_jabvox: true }
      attrs[:agent_id_jabvox] = user_id if log.agent_id_jabvox.blank? && user_id.present?
      log.update_columns(attrs) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] mark_dialer_answered failed | #{e.message}"
    end

    # Reuses the existing authenticated socket — avoids TCP+login overhead per Getvar.
    # Usa ActionID para casar la respuesta correcta (no un Pong ni otra respuesta)
    # y despacha por el camino cualquier evento que llegue, de modo que ningún
    # evento AMI se pierda mientras esperamos el valor de la variable.
    def getvar_on_existing(channel, variable)
      action_id = next_action_id
      send_action(@socket, 'Getvar', channel: channel, variable: variable, actionid: action_id)
      resp = await_response(action_id)
      resp['value']
    rescue StandardError
      nil
    end

    # AgentComplete fires when queue call ends — use as primary call_ended trigger.
    # Falls back to extension lookup in Redis if channel map isn't populated yet.
    def handle_agent_complete(event)
      queue     = event['queue'].to_s
      member    = event['interface'].presence || event['member'].to_s
      extension = strip_sip_prefix(member)

      Rails.logger.info "🔎 [AmiListener] AgentComplete | queue=#{queue} member=#{member} ext=#{extension}"
      return unless queue.start_with?('dialer_camp_') && extension.present?

      campaign_id = parse_campaign_id(queue)

      # Try channel map first
      channel = event['channel'].to_s
      info    = @active_channels.delete(channel)
      if info
        @active_channels.delete(info[:caller_channel])
        @active_channels.delete(info[:dest_channel])
        broadcast_call_ended_for(info[:user_id], info[:contact_id], campaign_id, extension)
        return
      end

      # Fallback: find agent by extension in Redis
      user_id, state = find_agent_by_extension(extension)
      return unless user_id && state

      broadcast_call_ended_for(user_id, nil, campaign_id, extension, state)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_agent_complete failed | #{e.message}"
    end

    # Un Originate async responde con OriginateResponse. Response=Failure significa
    # que la llamada NO se estableció (trunk congestionado, número inválido, canal
    # nunca creado). Sin manejarlo, el log quedaba 'initiated'/'calling' y el agente
    # pegado en "Marcando…" hasta el reaper (15 min). Aquí cerramos el log como
    # fallido y avisamos al frontend de inmediato.
    def handle_originate_response(event)
      return if event['response'].to_s.casecmp?('Success')

      channel = event['channel'].to_s
      log_id  = channel_var(channel, 'JABVOX_DIALER_LOG_ID', event)
      # Sin marcador (canal nunca creado): el reaper sigue siendo el respaldo.
      return if log_id.blank?
      return unless channel_belongs_to_account?(channel, 'JABVOX_ACCOUNT_ID', event)

      Rails.logger.info "📵 [AmiListener] OriginateResponse Failure | account=#{@account_id} log=#{log_id} reason=#{event['reason']}"
      close_dialer_log(log_id.to_i, event, status: 'failed')
      notify_dialer_call_ended(log_id.to_i)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_originate_response failed | #{e.message}"
    end

    def handle_hangup(event)
      channel = event['channel'].to_s
      handle_click_to_call_hangup(channel, event)
      handle_dialer_hangup(channel, event)
      # Release ALL cached markers for this call (every leg), not just this channel.
      clear_call_cache(event['linkedid'], channel)

      info = @active_channels.delete(channel)
      return unless info

      @active_channels.delete(info[:caller_channel])
      @active_channels.delete(info[:dest_channel])
      broadcast_call_ended_for(info[:user_id], info[:contact_id], info[:campaign_id], info[:extension])
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] handle_hangup failed | #{e.message}"
    end

    # Dialer legs carry a __JABVOX_DIALER_LOG_ID variable. On hangup, record the recording
    # uniqueid on the dialer call log so it links to CDR reports + analysis pipelines,
    # AND close the log so the campaign report is correct even in one-by-one mode,
    # where there is no queue (no AgentConnect/AgentComplete). Without this the log
    # stays 'initiated' forever and the report shows 0 answered.
    def handle_dialer_hangup(channel, event)
      return if channel.blank?

      log_id = channel_var(channel, 'JABVOX_DIALER_LOG_ID', event)
      # Fallback for dialplans where the log-id marker never reaches the hung-up leg:
      # close the agent's most recent open dialer log by extension (mirrors the
      # dialer's queue flow and click-to-call's extension fallback).
      log_id ||= fallback_dialer_log_id_by_extension(channel)
      return if log_id.blank?
      # Defence in depth: ignore events whose channel was originated by another account,
      # even when several accounts share one Asterisk server (the lookup is account-scoped too).
      return unless channel_belongs_to_account?(channel, 'JABVOX_ACCOUNT_ID', event)

      close_dialer_log(log_id.to_i, event)
      # En modo one-by-one NO hay cola (ni AgentConnect/AgentComplete), así que
      # @active_channels queda vacío y el broadcast de call_ended de handle_hangup
      # nunca se dispara: el agente se quedaba pegado "en llamada" y el marcador
      # no seguía. Avisamos al frontend directamente desde el log recién cerrado,
      # pase lo que pase con la llamada (no contesta / ocupado / falla / cuelgan).
      notify_dialer_call_ended(log_id.to_i)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] dialer hangup failed | #{e.message}"
    end

    # Emite call_ended hacia el frontend del agente a partir de un dialer call
    # log, sin depender de @active_channels (que solo se puebla en modo cola).
    # Es idempotente: si handle_hangup ya lo emitió, este segundo aviso es inocuo.
    def notify_dialer_call_ended(log_id)
      log = JabvoxDialerCallLog.find_by(id: log_id, account_id: @account_id)
      return unless log&.agent_id_jabvox

      broadcast_call_ended_for(log.agent_id_jabvox, log.jabvox_dialer_campaign_contact_id,
                               log.jabvox_dialer_campaign_id, log.phone_jabvox)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] notify_dialer_call_ended failed | #{e.message}"
    end

    # Finds the agent's most recent OPEN dialer log by the extension in the channel
    # name (SIP/<ext>-xxxx), used when JABVOX_DIALER_LOG_ID isn't on the hung-up leg.
    def fallback_dialer_log_id_by_extension(channel)
      ext = channel.to_s[%r{\ASIP/(\d{1,10})-}, 1]
      return if ext.blank?

      user_ext = JabvoxUserExtension.find_by(account_id: @account_id, extension_jabvox: ext)
      return if user_ext.nil?

      JabvoxDialerCallLog
        .where(account_id: @account_id, agent_id_jabvox: user_ext.user_id, status_jabvox: %w[initiated calling])
        .order(started_at_jabvox: :desc).first&.id
    rescue StandardError
      nil
    end

    # Records the recording uniqueid and finalizes an open dialer log on hangup.
    # A call that was answered by the customer has a non-empty ConnectedLineNum or a
    # positive billable duration; otherwise it did not connect (no-answer/busy).
    # status: fuerza el estado final (p. ej. 'failed' desde OriginateResponse).
    # Si es nil, se deduce de call_was_answered? (answered / no_answer).
    def close_dialer_log(log_id, event, status: nil)
      # Liberar el marcador de "ya avisé contestada" para que una re-marcación
      # del mismo lead vuelva a emitir call_assigned.
      @answered_logs&.delete(log_id)
      log = JabvoxDialerCallLog.find_by(id: log_id, account_id: @account_id)
      return if log.nil?

      uniqueid = event['uniqueid'].presence
      answered = status.nil? ? call_was_answered?(event) : false
      attrs = {}
      attrs[:uniqueid_jabvox] = uniqueid if uniqueid.present? && log.uniqueid_jabvox.blank?
      # Cerrar el log SIEMPRE: sin ended_at el log quedaba 'initiated' para
      # siempre (visto en producción: log 665) y el monitor lo mostraba como
      # llamada en curso indefinidamente.
      attrs[:ended_at_jabvox] = Time.current if log.ended_at_jabvox.blank?
      if log.started_at_jabvox.present? && log.duration_jabvox.to_i.zero?
        attrs[:duration_jabvox] = [(Time.current - log.started_at_jabvox).to_i, 0].max
      end

      # Only finalize logs still open; a queue flow may already have set 'answered'.
      if %w[initiated calling].include?(log.status_jabvox)
        attrs[:status_jabvox] = status || (answered ? 'answered' : 'no_answer')
        attrs[:lead_answered_jabvox] = answered
        # Mirror onto the campaign-contact so progress/report counts agree.
        finalize_contact_for_log(log, answered, status: status)
      end
      log.update_columns(attrs) if attrs.any? # rubocop:disable Rails/SkipsModelValidations
    end

    # A Hangup event marks a connected call via a non-zero answer/billable seconds
    # or a Cause of 16 (Normal Clearing) with a connected line. Falls back to the
    # presence of a bridged/connected line number.
    def call_was_answered?(event)
      # OJO: read_response baja TODAS las claves a minúsculas, así que hay que
      # leerlas en minúscula ('billableseconds', no 'BillableSeconds'). El bug
      # anterior (mayúsculas) hacía que billable fuera siempre 0 y una llamada
      # contestada se registrara como no_answer.
      billable = event['billableseconds'].to_i
      return true if billable.positive?

      # answeredtime/answer presente = hubo respuesta (algunos dialplans lo
      # reportan en el Hangup en vez de billableseconds).
      return true if event['answeredtime'].to_i.positive?

      # Si el canal ya estaba "Up" al colgar, la llamada estaba conectada.
      return true if event['channelstatedesc'].to_s.casecmp?('Up')

      # Último criterio: cierre normal (Cause 16) con línea conectada.
      cause = event['cause'].to_s
      connected = event['connectedlinenum'].to_s.gsub(/\D/, '')
      cause == '16' && connected.length >= 5
    end

    def finalize_contact_for_log(log, answered, status: nil)
      cc = JabvoxDialerCampaignContact.find_by(id: log.jabvox_dialer_campaign_contact_id)
      return if cc.nil? || cc.status_jabvox != 'calling'

      cc_status = status || (answered ? 'completed' : 'no_answer')
      cc.update_columns(status_jabvox: cc_status) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError
      nil
    end

    # Click-to-call legs carry a __CTCALL_ID variable. When such a channel hangs up,
    # record the recording uniqueid and notify the agent so the typify dialog opens.
    def handle_click_to_call_hangup(channel, event)
      return if channel.blank?

      call_log_id = channel_var(channel, 'CTCALL_ID', event)
      if call_log_id.present?
        # Defence in depth: only act on channels this account originated (CTCALL_ACCOUNT),
        # so a shared PBX with colliding extensions can't cross accounts.
        return unless channel_belongs_to_account?(channel, 'CTCALL_ACCOUNT', event)
      else
        # Fallbacks (in order) for dialplans that dial the trunk from a context,
        # where CTCALL_ID isn't on the hung-up leg. Any of these makes the typify
        # dialog fire no matter which leg (agent SIP, trunk, or MicroSIP) hangs up:
        #   1) by CTCALL_ID cached under the call's linkedid — when the CUSTOMER or
        #      MicroSIP hangs up, the Hangup comes from the trunk leg (SIP/ipcom-…),
        #      which has no CTCALL_ID and isn't "SIP/<ext>", but shares the linkedid
        #      with the agent leg that did carry it.
        #   2) by the agent extension in the channel name (SIP/1501-xxxx).
        #   3) by the dialed number matching a recent 'calling' log.
        call_log_id =
          fallback_ctc_by_linkedid(event) ||
          fallback_ctc_by_extension(channel) ||
          fallback_ctc_log_id(channel, event)
      end
      return if call_log_id.blank?

      uniqueid = event['uniqueid'].presence
      Jabvox::ClickToCallHangupService.new(@account_id, call_log_id.to_i, uniqueid).call
    end

    # Closes the click-to-call by CTCALL_ID cached under the call's linkedid/uniqueid.
    # handle_varset caches the marker under every correlation id (channel, uniqueid,
    # linkedid). When the customer or MicroSIP hangs up, the Hangup leg is the trunk
    # (no CTCALL_ID, not "SIP/<ext>"), but it shares the linkedid with the agent leg
    # that carried the marker — so we still find it here. Also scans @call_keys, the
    # linkedid→keys index, in case the marker was cached only under the agent leg's
    # channel/uniqueid but grouped under this linkedid.
    def fallback_ctc_by_linkedid(event)
      ids = [event['linkedid'], event['uniqueid']].map(&:to_s).reject(&:blank?).uniq
      ids.each do |id|
        cached = @channel_vars.dig(id, 'CTCALL_ID')
        return cached if cached.present?
      end
      # Widen: any key grouped under this call's linkedid may hold the marker.
      group = event['linkedid'].to_s
      (@call_keys[group] || []).each do |key|
        cached = @channel_vars.dig(key, 'CTCALL_ID')
        return cached if cached.present?
      end
      nil
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] fallback_ctc_by_linkedid failed | #{e.message}"
      nil
    end

    # Closes the click-to-call by the AGENT extension in the channel name. The
    # click-to-call originate rings "SIP/<ext>" first, so when THAT leg hangs up
    # (agent hangs from MicroSIP, or the call tears down) the channel is
    # "SIP/<ext>-xxxx". We map the extension to its agent and close that agent's
    # most recent 'calling' log. This mirrors how the dialer closes by extension.
    def fallback_ctc_by_extension(channel)
      ext = channel.to_s[%r{\ASIP/(\d{1,10})-}, 1]
      return if ext.blank?

      user_ext = JabvoxUserExtension.find_by(account_id: @account_id, extension_jabvox: ext)
      return if user_ext.nil?

      log = JabvoxCallLog.where(account_id: @account_id, user_id: user_ext.user_id, status: 'calling')
                         .where('called_at >= ?', CTC_FALLBACK_WINDOW.ago)
                         .order(called_at: :desc).first
      log&.id
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] fallback_ctc_by_extension failed | #{e.message}"
      nil
    end

    # Finds the click-to-call log to close when the CTCALL_ID marker isn't on the
    # hung-up channel. Matches this account's most recent 'calling' log whose
    # dialed number matches the channel's callerid/exten digits, created in the
    # last few minutes. Digits are compared by suffix so provider prefixes
    # ("0200218") and the "+"/country code never break the match.
    CTC_FALLBACK_WINDOW = 30.minutes
    MATCH_DIGITS = 8 # local subscriber number length — ignores prefixes/country code
    def fallback_ctc_log_id(_channel, event)
      # The dialed number comes from the exten (the number Asterisk dialed) — NOT
      # the channel name, which carries junk digits like "-3c" that corrupt it.
      dialed = event['exten'].to_s.gsub(/\D/, '')
      dialed = event['calleridnum'].to_s.gsub(/\D/, '') if dialed.length < MATCH_DIGITS
      return if dialed.length < MATCH_DIGITS

      # Match by the last N digits only, so a provider prefix ("0200218") or the
      # country code on either side never breaks the correlation.
      dialed_tail = dialed[-MATCH_DIGITS..]
      log = JabvoxCallLog.where(account_id: @account_id, status: 'calling')
                         .where('called_at >= ?', CTC_FALLBACK_WINDOW.ago)
                         .order(called_at: :desc)
                         .detect do |l|
        num = l.phone_number.to_s.gsub(/\D/, '')
        num.length >= MATCH_DIGITS && num[-MATCH_DIGITS..] == dialed_tail
      end
      log&.id
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] click_to_call hangup failed | #{e.message}"
    end

    # True when the channel's account-marker variable matches this listener's account.
    # If the variable is absent (older channels), we don't block — the account-scoped DB
    # lookup downstream is still the backstop.
    def channel_belongs_to_account?(channel, account_var, event = nil)
      value = channel_var(channel, account_var, event)
      return true if value.blank?

      value.to_s == @account_id.to_s
    end

    # Respaldo de AgentComplete cuando @active_channels ya no tiene el canal
    # (reconexión a mitad de llamada, reinicio del listener, eviction del cache):
    # localiza al agente por su extensión recorriendo los agentes conectados en
    # Redis. Devuelve [user_id, state] o [nil, nil]. Sin esto, handle_agent_complete
    # llamaba a un método inexistente y el fallback moría en silencio (NoMethodError
    # tragado), dejando al agente "en llamada" hasta que otro fallback lo rescatara.
    def find_agent_by_extension(extension)
      ext = extension.to_s
      return [nil, nil] if ext.blank?

      connected_agent_ids.each do |uid|
        state = read_agent_state_for(uid)
        next unless state && state[:extension].to_s == ext

        return [uid, state]
      end
      [nil, nil]
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] find_agent_by_extension failed | #{e.message}"
      [nil, nil]
    end

    def connected_agent_ids
      Redis::Alfred.smembers("jabvox_dialer_connected_#{@account_id}").map(&:to_i)
    rescue StandardError
      []
    end

    def read_agent_state_for(uid)
      raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account_id}_#{uid}")
      raw ? JSON.parse(raw, symbolize_names: true) : nil
    rescue StandardError
      nil
    end

    # Marca/limpia "en llamada" en el estado Redis del agente, para que el
    # reporte de agentes muestre el estado real (esperando / en llamada) en vivo.
    AGENT_STATE_TTL = 10.minutes.to_i

    def mark_agent_call(user_id, contact_id)
      key = "jabvox_dialer_agent_#{@account_id}_#{user_id}"
      raw = Redis::Alfred.get(key)
      return unless raw

      data = JSON.parse(raw, symbolize_names: true)
      if contact_id
        data[:in_call_contact_id] = contact_id
      else
        data.delete(:in_call_contact_id)
      end
      data[:state_changed_at] = Time.current.to_i
      Redis::Alfred.setex(key, data.to_json, AGENT_STATE_TTL)
      # Registrar la transición para el reporte de agentes. Al terminar la llamada,
      # el estado vuelve a 'paused' si el agente tenía un estado activo, o 'waiting'.
      state = if contact_id
                'in_call'
              else
                data[:state_id].present? ? 'paused' : 'waiting'
              end
      Jabvox::DialerAgentStateLogger.record(account_id: @account_id, user_id: user_id, state: state)
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] mark_agent_call failed | #{e.message}"
    end

    def broadcast_call_ended_for(user_id, contact_id, campaign_id, extension, state = nil)
      state ||= begin
        raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account_id}_#{user_id}")
        raw ? JSON.parse(raw, symbolize_names: true) : nil
      end
      mark_agent_call(user_id, nil)
      return unless state

      pubsub_token = state[:pubsub_token]
      return if pubsub_token.blank?

      Rails.logger.info "📵 [AmiListener] call_ended | account=#{@account_id} ext=#{extension} user=#{user_id}"

      Jabvox::DialerService.new(@config).pause_in_queue("dialer_camp_#{campaign_id}", extension, paused: true) if campaign_id.present?

      ActionCable.server.broadcast(
        pubsub_token,
        { event: 'jabvox.dialer.call_ended', data: { account_id: @account_id, user_id: user_id, dialer_contact_id: contact_id } }
      )
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] broadcast_call_ended_for failed | #{e.message}"
    end

    def broadcast_call_assigned(user_id, dialer_contact_id, campaign_id) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      account  = Account.find(@account_id)
      contact  = account.jabvox_dialer_campaign_contacts.find_by(id: dialer_contact_id)
      return unless contact

      crm      = Contact.find_by(id: contact.contact_id, account_id: @account_id)
      campaign = account.jabvox_dialer_campaigns.find_by(id: campaign_id)
      lead     = account.jabvox_leads.find_by(contact_id: contact.contact_id)
      return unless crm && campaign

      raw = Redis::Alfred.get("jabvox_dialer_agent_#{@account_id}_#{user_id}")
      return unless raw

      state        = JSON.parse(raw, symbolize_names: true)
      pubsub_token = state[:pubsub_token]
      return if pubsub_token.blank?

      conversation_id = find_or_create_conversation(account, crm, campaign)

      fv   = field_vis(account, user_id)
      attrs = crm.additional_attributes || {}
      data = {
        account_id: @account_id,
        dialer_contact_id: contact.id,
        user_id: user_id,
        contact_name: fv['name'] == false ? '***'         : crm.name.to_s,
        contact_phone: fv['phone'] == false ? '***'  : contact.phone_jabvox,
        contact_email: fv['email'] == false ? '***'        : crm.email.to_s,
        contact_country: fv['country'] == false ? '***' : crm.country_code.to_s,
        # Documento y tipo de persona: mismos campos que muestra el detalle del lead
        # (additional_attributes). El documento cae al helper de campos custom si no
        # está en additional_attributes, igual que el preview de la campaña.
        contact_document: fv['identification'] == false ? '***' : dialer_document(lead, attrs, crm),
        contact_type: fv['contact_type'] == false ? '***' : (attrs['jabvox_contact_type'].presence || 'persona'),
        contact_id: contact.contact_id,
        lead_id: lead&.id,
        lead_number: lead&.lead_number,
        affiliate_name: lead&.jabvox_affiliate&.name.to_s,
        campaign_name: lead&.jabvox_campaign&.name_jabvox.to_s,
        conversation_id: conversation_id,
        wrapup_seconds: campaign.wrapup_time_jabvox.to_i,
        management_history: fetch_mgmt_history(account, contact.contact_id)
      }

      mark_agent_call(user_id, contact.id)
      ActionCable.server.broadcast(pubsub_token, { event: 'jabvox.dialer.call_assigned', data: data })
      Rails.logger.info "📨 [AmiListener] call_assigned broadcast | account=#{@account_id} user=#{user_id} contact=#{dialer_contact_id}"
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListener] broadcast_call_assigned failed | #{e.message}"
    end

    # Documento del lead — cubre TODAS las fuentes posibles, en el mismo orden que
    # el detalle del lead + el preview de la campaña, para que funcione en cualquier
    # cuenta sin importar dónde viva el documento:
    #   1) additional_attributes.jabvox_identification_number (detalle del lead)
    #   2) campos custom del lead (documento/document/cedula/dni/nit/identificacion)
    #   3) contact.identifier (columna del contacto — último fallback del preview)
    def dialer_document(lead, attrs, crm)
      doc = attrs['jabvox_identification_number'].to_s
      return doc if doc.present?

      custom = lead&.custom_fields_jabvox || {}
      %w[documento document cedula dni nit identificacion identification].each do |k|
        v = custom[k].to_s
        return v if v.present?
      end
      crm&.identifier.to_s
    end

    # Devuelve el display_id (NO el id interno): la API de mensajes del frontend
    # resuelve la conversación por display_id. Antes devolvía el PK y el wrap-up
    # del marcador creaba la nota en la conversación equivocada, por lo que la
    # gestión no aparecía en el detalle del lead.
    def find_or_create_conversation(account, crm, campaign)
      existing = account.conversations.where(contact_id: crm.id).order(id: :desc).first
      return existing.display_id if existing

      inbox_id = (campaign.inbox_ids_jabvox || []).compact.map(&:to_i).find { |id| id.positive? } ||
                 account.inboxes.first&.id
      return nil unless inbox_id

      inbox = Inbox.find_by(id: inbox_id, account_id: account.id)
      return nil unless inbox

      contact_inbox = ContactInbox.find_or_create_by!(contact: crm, inbox: inbox) do |ci|
        ci.source_id = SecureRandom.uuid
      end

      Conversation.create!(
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: crm.id,
        contact_inbox_id: contact_inbox.id
      ).display_id
    rescue StandardError => e
      Rails.logger.warn "⚠️ [AmiListener] find_or_create_conversation failed | #{e.message}"
      nil
    end

    def field_vis(account, user_id)
      records = account.jabvox_field_visibilities.where(user_id: user_id)
      JabvoxFieldVisibility::FIELDS.index_with { true }.merge(
        records.each_with_object({}) { |v, h| h[v.field_name] = v.can_view }
      )
    end

    def fetch_mgmt_history(account, contact_id, limit: 8)
      return [] unless contact_id

      Message.joins(:conversation)
             .where(conversations: { account_id: account.id, contact_id: contact_id })
             .where(private: true)
             .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
             .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
             .order(id: :desc)
             .limit(limit)
             .map do |msg|
               { state_name: msg.content_attributes['jabvox_management_state_name'],
                 state_color: msg.content_attributes['jabvox_management_state_color'],
                 note: msg.content,
                 created_at: msg.created_at.strftime('%d/%m %H:%M') }
             end
    rescue StandardError
      []
    end

    def strip_sip_prefix(member)
      member.sub(%r{\ASIP/}i, '').sub(%r{\APJSIP/}i, '')
    end

    def parse_campaign_id(queue)
      queue.sub('dialer_camp_', '').to_i
    end

    # Saneo CRLF en clave y valor: ningún dato puede incrustar saltos de línea que
    # AMI interpretaría como acciones/claves extra (defensa en profundidad).
    def send_action(socket, action, **params)
      msg = "Action: #{action.to_s.delete("\r\n")}\r\n"
      params.each { |key, val| msg << "#{key.to_s.delete("\r\n")}: #{val.to_s.delete("\r\n")}\r\n" }
      msg << "\r\n"
      socket.write(msg)
    end

    # Máximo que esperamos por una LÍNEA dentro de un bloque de respuesta ya
    # empezado. Sin esto, un socket que se queda a medias (evento parcial, red
    # colgada) bloqueaba socket.gets para siempre y congelaba el listener sin
    # reconectar. Al vencer, lanzamos para que el loop de run reconecte.
    READ_LINE_TIMEOUT = 20

    def read_response(socket)
      result = {}
      loop do
        raise 'AMI read timeout' unless IO.select([socket], nil, nil, READ_LINE_TIMEOUT)

        line = socket.gets
        raise 'AMI connection closed' if line.nil?

        line = line.chomp
        break if line.empty?

        key, val = line.split(': ', 2)
        result[key.downcase] = val if key && val
      end
      result
    end
  end
end
