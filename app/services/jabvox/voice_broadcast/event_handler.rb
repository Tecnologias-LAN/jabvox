# frozen_string_literal: true

# Traduce los eventos AMI del voice broadcast al desenlace de cada destinatario.
# Idempotente y tolerante a duplicados/orden: SIEMPRE se ancla al recipient por el
# JABVOX_VB_RECIPIENT_ID del canal (o el ActionID "jabvoxvb-<id>" en el
# OriginateResponse), NUNCA por "el más reciente". Aislado por account_id.
#
# El dialplan del agente virtual emite estos UserEvents (a documentar/instalar en el
# PBX): AmdResult (Status=HUMAN/MACHINE/NOTSURE), BroadcastPlayed (audio completo),
# DtmfCaptured (Digit=...). Además reacciona a OriginateResponse y Hangup.
#
# INDEPENDIENTE del marcador: las variables __JABVOX_VB_* viajan heredables y llegan
# como claves del propio evento AMI (minúsculas). El listener AMI es OPCIONAL: si se
# pasa, se usa como fallback para leer la variable del canal (cache/Getvar); si no,
# el handler funciona igual leyendo del evento y anclando por el ActionID.
class Jabvox::VoiceBroadcast::EventHandler
  def initialize(account_id, listener = nil)
    @account_id = account_id
    @listener = listener
  end

  def handle(evt_name, event)
    recipient = resolve_recipient(event)
    return if recipient.nil?

    case evt_name
    when 'userevent'        then handle_user_event(recipient, event)
    when 'dtmfend'          then handle_dtmf(recipient, event['digit'].to_s)
    when 'originateresponse' then handle_originate_response(recipient, event)
    when 'newstate'         then handle_newstate(recipient, event)
    when 'hangup'           then handle_hangup(recipient, event)
    end
  end

  # Newstate "Up" (channelstate 6) = la persona contestó. Registra el instante y el
  # tiempo de timbrado (ring) desde el último intento hasta ahora. Idempotente.
  def handle_newstate(recipient, event)
    state = (event['channelstate'] || event['channelstatedesc']).to_s
    return unless state == '6' || state.casecmp?('Up')
    return if recipient.answered_at_jabvox.present? # ya registrado

    now = Time.current
    ring = recipient.last_attempt_at_jabvox ? ((now - recipient.last_attempt_at_jabvox) * 1000).to_i : nil
    recipient.update_columns( # rubocop:disable Rails/SkipsModelValidations
      answered_at_jabvox: now,
      ring_ms_jabvox: ring&.clamp(0, 600_000)
    )
  end

  private

  # Ancla al destinatario por varias vías, en orden de fiabilidad (account-scoped):
  #   1) Variable del canal JABVOX_VB_RECIPIENT_ID (UserEvent/DtmfEnd la llevan).
  #   2) ActionID "jabvoxvb-<id>" (OriginateResponse lo devuelve tal cual).
  #   3) uniqueid / linkedid ya guardados en un destinatario (para el Hangup, que NO
  #      trae ni la variable ni el actionid, pero sí el uniqueid que anclamos antes).
  # Esto hace robusto el cierre de la llamada incluso cuando el evento reporta la
  # pierna del trunk (Local/SIP@trunk) sin las variables heredables.
  def resolve_recipient(event)
    # El dialplan (v2) incluye el recipient id en cada UserEvent como 'JabvoxVbRecipientId'
    # (llega en minúscula sin separadores); también lo buscamos como variable de canal.
    rid = event['jabvoxvbrecipientid'].presence ||
          channel_var(event, 'JABVOX_VB_RECIPIENT_ID')
    rid = rid.presence || recipient_id_from_action_id(event['actionid'])
    return JabvoxVoiceBroadcastRecipient.find_by(id: rid.to_i, account_id: @account_id) if rid.present?

    resolve_by_uniqueid(event)
  end

  # Resuelve por uniqueid/linkedid guardado (Hangup y otros eventos sin marcador).
  def resolve_by_uniqueid(event)
    ids = [event['uniqueid'], event['linkedid']].compact.reject(&:blank?)
    return nil if ids.empty?

    JabvoxVoiceBroadcastRecipient
      .where(account_id: @account_id)
      .where('uniqueid_jabvox IN (:ids) OR linkedid_jabvox IN (:ids)', ids: ids)
      .order(id: :desc).first
  end

  def recipient_id_from_action_id(action_id)
    m = action_id.to_s.match(/\Ajabvoxvb-(\d+)\z/)
    m && m[1]
  end

  # Lee una variable del canal SIN depender del listener: primero la busca como clave
  # del propio evento (las __JABVOX_VB_* heredables llegan así, en minúscula, p.ej.
  # 'jabvox_vb_recipient_id'); si no está y hay listener, usa su cache/Getvar.
  def channel_var(event, var)
    from_event = event[var.downcase] || event[var]
    return from_event if from_event.present?

    return nil unless @listener

    @listener.send(:channel_var, event['channel'].to_s, var, event)
  rescue StandardError
    nil
  end

  # UserEvent: distingue por el UserEvent name que emite el dialplan.
  def handle_user_event(recipient, event)
    name = (event['userevent'] || event['user-event']).to_s
    case name
    when 'AmdResult'      then apply_amd(recipient, event['status'].to_s)
    when 'BroadcastPlayed' then mark_played_complete(recipient)
    when 'DtmfCaptured'   then handle_dtmf(recipient, event['digit'].to_s)
    when 'VbHangup'       then handle_vb_hangup(recipient, event)
    end
  end

  # AMD: registra HUMAN/MACHINE/NOTSURE. Un MACHINE cierra el destinatario como
  # contestador (no se le reproduce el audio; el dialplan cuelga).
  def apply_amd(recipient, status)
    st = status.upcase
    st = 'NOTSURE' unless JabvoxVoiceBroadcastRecipient::AMD_STATUSES.include?(st)
    return if recipient.amd_status_jabvox.present? # idempotente

    recipient.update_columns(amd_status_jabvox: st) # rubocop:disable Rails/SkipsModelValidations
    return unless st == 'MACHINE'

    finalize(recipient, outcome: 'answered_machine', status: 'done')
    increment_broadcast(recipient, :answered_machine_count_jabvox)
  end

  def mark_played_complete(recipient)
    # Reprodujo el audio → contestó: captura el answer (answered_at/ring) si el Newstate
    # no ancló. NO cierra aquí: el cierre lo hace VbHangup (exten => h del dialplan), que
    # trae los tiempos REALES del CDR (billsec/duration). Así la duración escuchada queda
    # correcta y no en 0. Si el VbHangup nunca llegara, el reaper cierra como respaldo.
    ensure_answered(recipient)
    return if recipient.played_full_jabvox # idempotente

    recipient.update_columns(played_full_jabvox: true) # rubocop:disable Rails/SkipsModelValidations
    increment_broadcast(recipient, :played_complete_count_jabvox)
  end

  # Marca el instante de contestación (y el ring) si aún no se registró.
  def ensure_answered(recipient)
    return if recipient.answered_at_jabvox.present?

    now = Time.current
    ring = recipient.last_attempt_at_jabvox ? ((now - recipient.last_attempt_at_jabvox) * 1000).to_i : nil
    recipient.update_columns( # rubocop:disable Rails/SkipsModelValidations
      answered_at_jabvox: now, ring_ms_jabvox: ring&.clamp(0, 600_000)
    )
  end

  # DTMF: guarda la tecla. Si coincide con el dígito de opt-out del broadcast,
  # registra el desenlace opted_out y añade el número a la DNC de la cuenta.
  def handle_dtmf(recipient, digit)
    return if digit.blank? || recipient.dtmf_pressed_jabvox.present?

    recipient.update_columns(dtmf_pressed_jabvox: digit) # rubocop:disable Rails/SkipsModelValidations
    broadcast = recipient.jabvox_voice_broadcast
    return unless broadcast&.dtmf_enabled_jabvox && digit == broadcast.dtmf_optout_digit_jabvox.to_s

    finalize(recipient, outcome: 'opted_out', status: 'done')
    add_to_dnc(recipient.phone_jabvox)
  end

  # OriginateResponse: SIEMPRE estampa el uniqueid/linkedid del canal (ancla por el
  # ActionID "jabvoxvb-<id>", que este evento sí devuelve), para que el Hangup posterior
  # —que no trae ni la variable ni el actionid— pueda resolverse por ese uniqueid.
  # Si el Originate FALLÓ, además cierra el destinatario con el outcome según la causa.
  def handle_originate_response(recipient, event)
    stamp_uniqueid(recipient, event)
    return if event['response'].to_s.casecmp?('Success')
    return unless recipient.status_jabvox == 'calling'

    outcome = originate_failure_outcome(event['reason'].to_s)
    # Guarda el motivo del originate fallido (response + reason) para el reporte, así el
    # error queda registrado igual que en el CDR del PBX y no como un "failed" a secas.
    reason_txt = "OriginateResponse: #{event['response']}" \
                 "#{" (reason #{event['reason']})" if event['reason'].present?}"
    finalize(recipient, outcome: outcome, status: retry_or_fail(recipient, outcome),
                        extra: { hangup_cause_jabvox: reason_txt })
    increment_broadcast(recipient, :failed_count_jabvox) if outcome == 'failed'
  end

  # Hangup: cierra el destinatario si aún estaba 'calling'. Se considera CONTESTADA si:
  #   - billsec > 0 (algunos PBX lo reportan), o
  #   - el canal estaba "Up" (channelstate 6) al colgar (Issabel/Asterisk lo reporta así
  #     aunque no traiga billableseconds), o
  #   - AMD detectó HUMAN, o ya teníamos answered_at (Newstate Up previo).
  # Así no se marca no_answer una llamada que sí contestó.
  def handle_hangup(recipient, event) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless recipient.status_jabvox == 'calling'

    billsec = event['billableseconds'].to_i
    channel_up = event['channelstate'].to_s == '6' || event['channelstatedesc'].to_s.casecmp?('Up')
    answered = billsec.positive? || channel_up || recipient.amd_status_jabvox == 'HUMAN' ||
               recipient.answered_at_jabvox.present?
    outcome = answered ? 'answered_human' : hangup_no_answer_outcome(event)
    stamp_uniqueid(recipient, event)
    # Duración: billsec si vino; si no y contestó, calcula desde answered_at; si no, lo previo.
    dur = if billsec.positive?
            billsec * 1000
          elsif answered && recipient.answered_at_jabvox
            ((Time.current - recipient.answered_at_jabvox) * 1000).to_i
          else
            recipient.duration_ms_jabvox
          end
    extra = { duration_ms_jabvox: dur }
    rec_file = event['recording_file'].presence || event['recordingfile'].presence
    extra[:recording_file_jabvox] = rec_file if rec_file.present?
    # Causa COMPLETA (código Q.850 + texto legible, como el CDR de Issabel), no solo el nº.
    extra[:hangup_cause_jabvox] = hangup_cause_text(event) || event['cause'].presence
    finalize(recipient, outcome: outcome, status: retry_or_fail(recipient, outcome), extra: extra)
    increment_broadcast(recipient, :answered_human_count_jabvox) if outcome == 'answered_human'
  end

  # VbHangup: evento de cierre que el dialplan (exten => h) emite SIEMPRE con el
  # JabvoxVbRecipientId, para cerrar el destinatario de forma fiable aunque el Hangup
  # crudo no ancle (con canales Local hay varias piernas y uniqueid distinto). Contesta
  # si billsec>0, si reprodujo el audio (Played=1), o si ya se marcó answered.
  def handle_vb_hangup(recipient, event)
    return unless recipient.reload.status_jabvox == 'calling'

    billsec = event['billsec'].to_i
    duration = event['duration'].to_i
    played = event['played'].to_s == '1' || recipient.played_full_jabvox
    answered = billsec.positive? || played || recipient.amd_status_jabvox == 'HUMAN' ||
               recipient.answered_at_jabvox.present?
    outcome = answered ? 'answered_human' : 'no_answer'
    finalize(recipient, outcome: outcome, status: retry_or_fail(recipient, outcome),
                        extra: { duration_ms_jabvox: answered_duration_ms(recipient, billsec, duration) })
    increment_broadcast(recipient, :answered_human_count_jabvox) if outcome == 'answered_human'
  end

  # Duración escuchada, en ms, con el mejor dato disponible: billsec del CDR (segundos
  # hablando = tiempo de audio) → duración total del CDR → desde answered_at → lo previo.
  def answered_duration_ms(recipient, billsec, duration = 0)
    if billsec.positive?
      billsec * 1000
    elsif duration.positive?
      duration * 1000
    elsif recipient.answered_at_jabvox
      [((Time.current - recipient.answered_at_jabvox) * 1000).to_i, 0].max
    else
      recipient.duration_ms_jabvox
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  # Campos del `extra` que existen en recipients (los demás, como hangup_cause, solo
  # viven en el call_log histórico, no en la fila del destinatario).
  RECIPIENT_EXTRA_KEYS = %i[duration_ms_jabvox recording_file_jabvox].freeze

  def finalize(recipient, outcome:, status:, extra: {})
    recipient_extra = extra.slice(*RECIPIENT_EXTRA_KEYS).compact
    attrs = { outcome_jabvox: outcome, status_jabvox: status }.merge(recipient_extra)
    recipient.update_columns(attrs) # rubocop:disable Rails/SkipsModelValidations
    # Registra ESTA llamada individual en el histórico (una fila por intento), para el
    # reporte completo aunque el destinatario se reintente y sobrescriba su fila.
    record_call_log(recipient.reload, outcome, extra)
    # Contador de marcados: sube una sola vez cuando el destinatario deja 'calling'.
    increment_broadcast(recipient, :dialed_count_jabvox)
    # Auto-completa la campaña si este cierre fue el último (sin esperar al próximo tick),
    # para que el estado se refleje al instante en la UI.
    complete_broadcast_if_done(recipient.jabvox_voice_broadcast_id)
  end

  # Marca la campaña 'completed' si ya no quedan pendientes ni llamadas en vuelo.
  def complete_broadcast_if_done(broadcast_id)
    bcast = JabvoxVoiceBroadcast.find_by(id: broadcast_id)
    return unless bcast&.status_jabvox == 'running'
    return unless bcast.remaining_recipients_count.zero? && bcast.in_flight_count.zero?

    bcast.update_columns(status_jabvox: 'completed', finished_at_jabvox: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] complete_if_done failed | #{e.message}"
  end

  # Persiste una fila por llamada en jabvox_voice_broadcast_call_logs. Idempotente por
  # uniqueid: si ya existe un log con ese uniqueid, lo actualiza en vez de duplicar.
  def record_call_log(recipient, outcome, extra) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    attrs = {
      jabvox_voice_broadcast_id: recipient.jabvox_voice_broadcast_id,
      account_id: recipient.account_id,
      contact_id: recipient.contact_id,
      phone_jabvox: recipient.phone_jabvox,
      name_jabvox: recipient.name_jabvox,
      attempt_number_jabvox: recipient.attempts_jabvox.to_i,
      outcome_jabvox: outcome,
      amd_status_jabvox: recipient.amd_status_jabvox,
      dtmf_pressed_jabvox: recipient.dtmf_pressed_jabvox,
      played_full_jabvox: recipient.played_full_jabvox,
      duration_ms_jabvox: extra[:duration_ms_jabvox] || recipient.duration_ms_jabvox,
      recording_file_jabvox: extra[:recording_file_jabvox] || recipient.recording_file_jabvox,
      uniqueid_jabvox: recipient.uniqueid_jabvox,
      linkedid_jabvox: recipient.linkedid_jabvox,
      hangup_cause_jabvox: extra[:hangup_cause_jabvox],
      answered_at_jabvox: recipient.answered_at_jabvox,
      ring_ms_jabvox: recipient.ring_ms_jabvox,
      started_at_jabvox: recipient.last_attempt_at_jabvox,
      ended_at_jabvox: Time.current,
      # Duración TOTAL de la llamada (ring + conversación), desde el originate al hangup.
      total_duration_ms_jabvox: recipient.last_attempt_at_jabvox ? ((Time.current - recipient.last_attempt_at_jabvox) * 1000).to_i : nil
    }
    # Idempotencia: busca un log existente por uniqueid; si no hay uniqueid (originate
    # perdido o cierre por reaper), deduplica por (recipient, nº de intento) para NO
    # crear filas repetidas del mismo intento que inflarían el reporte.
    uid = recipient.uniqueid_jabvox
    log = if uid.present?
            JabvoxVoiceBroadcastCallLog.find_by(uniqueid_jabvox: uid, jabvox_voice_broadcast_recipient_id: recipient.id)
          else
            JabvoxVoiceBroadcastCallLog.find_by(jabvox_voice_broadcast_recipient_id: recipient.id,
                                                attempt_number_jabvox: recipient.attempts_jabvox.to_i, uniqueid_jabvox: nil)
          end
    if log
      log.update_columns(attrs.except(:started_at_jabvox)) # rubocop:disable Rails/SkipsModelValidations
    else
      JabvoxVoiceBroadcastCallLog.create!(attrs.merge(jabvox_voice_broadcast_recipient_id: recipient.id))
    end
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] record_call_log failed | #{e.message}"
  end

  # Reintento: si el outcome es reintentable y no agotó max_retries, vuelve a
  # 'pending' (el motor lo re-marcará tras el intervalo); si no, 'done'/'failed'.
  def retry_or_fail(recipient, outcome)
    broadcast = recipient.jabvox_voice_broadcast
    if JabvoxVoiceBroadcastRecipient::RETRYABLE_OUTCOMES.include?(outcome) &&
       recipient.retryable?(broadcast&.max_retries_jabvox, outcome)
      'pending'
    else
      outcome == 'failed' ? 'failed' : 'done'
    end
  end

  # `Reason` del OriginateResponse (distinto de los cause Q.850). Asterisk:
  #   0/1 = no contestó/timeout · 4 = contestó · 5 = ocupado/congestión ·
  #   8 = colgado. El resto lo tratamos como fallo del originate.
  def originate_failure_outcome(reason)
    case reason.to_s
    when '0', '1' then 'no_answer'
    when '5'      then 'congestion' # busy/congestion a nivel de originate
    else 'failed'
    end
  end

  # Códigos de causa Q.850 (ISDN) que Asterisk/Issabel adjunta al Hangup, con su
  # descripción legible (la MISMA que muestra el CDR de Issabel) y el outcome de negocio.
  # Fuente: causas estándar de Asterisk (AST_CAUSE_*). Guardamos texto+código completos
  # para que el reporte muestre el error real, no solo un "failed" genérico.
  HANGUP_CAUSES = {
    '1'  => ['Número no asignado / inexistente', 'failed'],
    '2'  => ['Sin ruta a la red especificada', 'failed'],
    '3'  => ['Sin ruta al destino', 'failed'],
    '16' => ['Corte normal', 'no_answer'],
    '17' => ['Ocupado', 'busy'],
    '18' => ['El usuario no responde', 'no_answer'],
    '19' => ['No contesta (alertando sin respuesta)', 'no_answer'],
    '20' => ['Abonado ausente', 'no_answer'],
    '21' => ['Llamada rechazada', 'failed'],
    '22' => ['Número cambió', 'failed'],
    '27' => ['Destino fuera de servicio', 'failed'],
    '28' => ['Número inválido / formato incorrecto', 'failed'],
    '29' => ['Facilidad rechazada', 'failed'],
    '31' => ['Normal, sin especificar', 'no_answer'],
    '34' => ['Sin circuito/canal disponible', 'congestion'],
    '38' => ['Red fuera de servicio', 'congestion'],
    '41' => ['Fallo temporal', 'congestion'],
    '42' => ['Congestión del conmutador', 'congestion'],
    '44' => ['Canal solicitado no disponible', 'congestion'],
    '58' => ['Capacidad no disponible', 'failed'],
    '88' => ['Destino incompatible', 'failed'],
    '102' => ['Recuperación por expiración de temporizador', 'no_answer']
  }.freeze

  # Texto completo de la causa Q.850 para guardar (ej. "34 - Sin circuito/canal
  # disponible"). Si Asterisk mandó `causetxt`/`cause-txt`, lo preferimos (es su
  # descripción exacta); si no, usamos nuestra tabla; si el código es desconocido,
  # guardamos al menos el número.
  def hangup_cause_text(event)
    code = event['cause'].to_s.strip
    txt = asterisk_cause_txt(event)
    return nil if code.blank? && txt.blank?

    mapped = HANGUP_CAUSES[code]&.first
    label = txt.presence || mapped
    label.present? ? "#{code} - #{label}" : code
  end

  # Descripción de causa que envía Asterisk (varía el nombre del campo según versión).
  def asterisk_cause_txt(event)
    (event['causetxt'] || event['cause-txt'] || event['causestr']).to_s.strip
  end

  # Outcome de negocio a partir del cause Q.850 (cuando el Hangup NO fue contestado).
  def hangup_no_answer_outcome(event)
    code = event['cause'].to_s.strip
    HANGUP_CAUSES[code]&.last || 'no_answer'
  end

  def stamp_uniqueid(recipient, event)
    uid = event['uniqueid'].presence
    lid = event['linkedid'].presence
    attrs = {}
    attrs[:uniqueid_jabvox] = uid if uid && recipient.uniqueid_jabvox.blank?
    attrs[:linkedid_jabvox] = lid if lid && recipient.linkedid_jabvox.blank?
    recipient.update_columns(attrs) if attrs.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def increment_broadcast(recipient, column)
    JabvoxVoiceBroadcast.where(id: recipient.jabvox_voice_broadcast_id)
                        .update_all("#{column} = #{column} + 1") # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError
    nil
  end

  # Añade el número a la lista de exclusión de la cuenta, si el módulo DNC existe.
  def add_to_dnc(phone)
    acc = Account.find_by(id: @account_id)
    return unless acc.respond_to?(:jabvox_dnc_entries)

    digits = phone.to_s.gsub(/\D/, '')
    return if digits.blank?

    acc.jabvox_dnc_entries.find_or_create_by(phone_jabvox: digits)
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] add_to_dnc failed | #{e.message}"
  end
end
