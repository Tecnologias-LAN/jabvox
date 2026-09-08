# frozen_string_literal: true

# Motor de marcación del voice broadcast. En cada tick (job cron) origina tantas
# llamadas como permita el pacing: hasta max_concurrent canales simultáneos, con un
# tope de CPS (llamadas por segundo) por corrida, respetando la ventana horaria y la
# lista de exclusión (DNC). Idempotente y aislado por cuenta:
#   - Lock Redis por broadcast: dos ticks solapados no doble-marcan.
#   - Reserva atómica del destinatario (pending → calling) antes del Originate.
#   - DNC verificada ANTES de marcar (cumplimiento legal).
# NO usa la Queue del dialer; origina hacia el contexto dialer-voicebot.
class Jabvox::VoiceBroadcast::DialEngine
  # TTL base del lock por broadcast; el heartbeat (RedisLock) lo renueva mientras el
  # tick origina llamadas, así un tick largo (llenando muchos slots) nunca deja expirar
  # el lock a mitad y no hay doble-marcación.
  TICK_LOCK_TTL = 90
  # Un tick no origina por más de esto (aunque queden slots libres): así no acapara el
  # worker de la cola. El siguiente tick (cron, cada minuto) continúa llenando. Con
  # campañas grandes + varios slots, un tick llena buena parte y el resto sigue enseguida.
  MAX_TICK_SECONDS = 45

  def self.tick(broadcast)
    new(broadcast).tick
  end

  def initialize(broadcast)
    @broadcast = broadcast
    @account = broadcast.account
  end

  # Un destinatario no puede quedar en 'calling' más que esto: si el evento de cierre
  # (Hangup/OriginateResponse) se pierde, el reaper lo rescata para que no bloquee el
  # slot de concurrencia ni deje la campaña colgada sin completarse nunca. Debe ser
  # mayor que el timeout del Originate (30s) + el tiempo del audio, con margen.
  STUCK_CALL_TIMEOUT = 180 # segundos

  # Devuelve el nº de llamadas originadas en este tick.
  def tick
    return 0 unless @broadcast.running?
    return 0 if auto_stop_if_expired # kill-switch por vida máxima de campaña
    return 0 unless within_operating_window?

    result = Jabvox::RedisLock.with_lock(tick_lock_key, ttl: TICK_LOCK_TTL) do |lock|
      reap_stuck_recipients
      originated = dial_batch(lock)
      finish_if_done
      originated
    end
    result == Jabvox::RedisLock::NOT_ACQUIRED ? 0 : result
  end

  # ¿La campaña sigue teniendo trabajo (running + pendientes o llamadas en vuelo)? El
  # TickAccountJob lo usa para RE-ENCOLARSE de inmediato cuando el tick terminó por tiempo
  # (MAX_TICK_SECONDS) pero aún queda por marcar — así la marcación es CONTINUA y no espera
  # al próximo cron (evita el gap de ~15s/minuto). El lock por broadcast impide solaparse.
  def more_work?
    @broadcast.reload.running? &&
      (@broadcast.remaining_recipients_count.positive? || @broadcast.in_flight_count.positive?)
  rescue StandardError
    false
  end

  private

  # Kill-switch: si la campaña lleva 'running' más que MAX_RUNTIME_HOURS, se auto-detiene
  # aunque queden pendientes. Blindaje final contra marcación indefinida si algo falla.
  def auto_stop_if_expired
    started = @broadcast.started_at_jabvox
    return false if started.blank?
    return false if started > JabvoxVoiceBroadcast::MAX_RUNTIME_HOURS.hours.ago

    @broadcast.update_columns(status_jabvox: 'stopped', finished_at_jabvox: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn "[VoiceBroadcast] auto-stopped by max runtime | broadcast=#{@broadcast.id}"
    true
  end

  # Rescata destinatarios pegados en 'calling' cuyo evento de cierre nunca llegó
  # (llamada perdida a nivel AMI). Los trata como 'no_answer' para que apliquen la
  # política de reintentos normal (o se cierren si agotaron intentos). Sin esto, un
  # solo evento perdido bloquea un slot de concurrencia para siempre.
  def reap_stuck_recipients
    cutoff = STUCK_CALL_TIMEOUT.seconds.ago
    stuck = @broadcast.recipients
                      .where(status_jabvox: 'calling')
                      .where('last_attempt_at_jabvox IS NULL OR last_attempt_at_jabvox < ?', cutoff)
    stuck.find_each do |rec|
      handler = Jabvox::VoiceBroadcast::EventHandler.new(@account.id)
      # Sintetiza un Hangup 'no answer' (billsec 0) anclado por el uniqueid del recipient.
      handler.handle('hangup', {
                       'uniqueid' => rec.uniqueid_jabvox.to_s,
                       'jabvox_vb_recipient_id' => rec.id.to_s,
                       'billableseconds' => '0',
                       'cause' => '18' # no user responding
                     })
    rescue StandardError => e
      Rails.logger.warn "[VoiceBroadcast] reap stuck recipient #{rec.id} failed | #{e.message}"
    end
  end

  # Cuánto espera el bucle cuando NO hay slots libres (todos los canales ocupados),
  # antes de volver a mirar si alguna llamada colgó y liberó un cupo. Corto para que el
  # relleno sea fluido (rellena en cuanto cuelgan), sin martillar la BD.
  REFILL_POLL_SECONDS = 0.5

  # PACING CONTINUO: mantiene SIEMPRE ~max_concurrent llamadas en vuelo durante todo el
  # tick, rellenando a medida que las llamadas van colgando (no por lotes). En cada vuelta
  # recalcula los cupos libres (max_concurrent - in_flight REAL) y origina para llenarlos
  # al ritmo del CPS; si no hay cupos, espera un poco y reintenta hasta agotar el tiempo del
  # tick o quedarse sin pendientes. El siguiente tick (cron cada minuto) continúa.
  #
  # Antes se calculaba `slots` UNA sola vez al inicio: marcaba 20 y no rellenaba hasta el
  # próximo tick (1 min después) → efecto "por lotes" (marca 20, espera a que acaben, marca
  # 20…). Ahora es un flujo continuo: marca 20, cuelgan 4 → marca 4, cuelgan 10 → marca 10.
  def dial_batch(lock) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    config = @account.jabvox_voip_config
    return 0 if config&.host.blank?

    ctx = {
      pause: 1.0 / [@broadcast.cps_jabvox.to_i, 1].max, # segundos entre originates (CPS real)
      deadline: Time.current + MAX_TICK_SECONDS,
      service: Jabvox::VoiceBroadcast::OriginateService.new(config),
      playback: Jabvox::VoiceBroadcast::DeployService.playback_ref(@broadcast.audio_filename_jabvox)
    }
    count = 0
    while Time.current < ctx[:deadline] && lock.held?
      slots = @broadcast.max_concurrent_jabvox - @broadcast.in_flight_count
      if slots <= 0
        nap_until(ctx[:deadline]) # canales llenos: espera a que alguna cuelgue
        next
      end

      originated = fill_free_slots(lock, ctx, slots)
      count += originated
      next if originated.positive? # marcó algo: sigue rellenando de inmediato

      # No marcó nada (cupos libres pero sin pendientes elegibles AHORA): si ya no queda
      # nada, terminamos; si solo faltan reintentos en espera o hay llamadas en vuelo,
      # esperamos y reintentamos (se rellenan al colgar / cumplir su intervalo).
      break if @broadcast.remaining_recipients_count.zero? && @broadcast.in_flight_count.zero?

      nap_until(ctx[:deadline])
    end
    count
  end

  # Origina hasta `slots` llamadas en esta vuelta, al ritmo del CPS. Devuelve cuántas marcó.
  def fill_free_slots(lock, ctx, slots)
    originated = 0
    slots.times do
      break unless lock.held?
      break if Time.current >= ctx[:deadline]

      recipient = reserve_next_recipient
      break if recipient.nil? # no quedan pendientes elegibles

      originate(ctx[:service], recipient, ctx[:playback])
      originated += 1
      sleep ctx[:pause]
    end
    originated
  end

  # Espera hasta REFILL_POLL_SECONDS (sin pasarse del deadline del tick).
  def nap_until(deadline)
    sleep REFILL_POLL_SECONDS.clamp(0, [deadline - Time.current, 0].max)
  end

  # Reserva atómica del siguiente destinatario pendiente (pending → calling) para
  # que dos ticks/procesos no tomen el mismo. Excluye números en la DNC de la
  # cuenta ANTES de marcar (cumplimiento). Devuelve el recipient o nil.
  def reserve_next_recipient
    JabvoxVoiceBroadcastRecipient.transaction do
      # Solo destinatarios elegibles AHORA: nunca intentados, o cuyo último intento fue
      # hace más del retry_interval (respeta el tiempo de espera entre reintentos, así un
      # no_answer que volvió a 'pending' no se re-marca en el tick inmediato).
      interval = @broadcast.retry_interval_jabvox.to_i
      cutoff = interval.positive? ? interval.seconds.ago : Time.current
      rec = @broadcast.recipients
                      .where(status_jabvox: 'pending')
                      .where('last_attempt_at_jabvox IS NULL OR last_attempt_at_jabvox <= ?', cutoff)
                      .order(:id).lock('FOR UPDATE SKIP LOCKED').first
      next nil if rec.nil?

      if dnc_blocked?(rec.phone_jabvox)
        # Número en DNC: se cierra como opt-out y NO se marca (el caller filtra :skip).
        rec.update_columns(status_jabvox: 'done', outcome_jabvox: 'opted_out') # rubocop:disable Rails/SkipsModelValidations
        next :skip
      end
      # Limpia los identificadores del canal del intento ANTERIOR: si no, el
      # OriginateResponse del nuevo intento no los reescribe (stamp es idempotente
      # sobre blanco) y el Hangup nuevo, con otro uniqueid, no ancla → se queda pegado.
      rec.update_columns( # rubocop:disable Rails/SkipsModelValidations
        status_jabvox: 'calling',
        attempts_jabvox: rec.attempts_jabvox.to_i + 1,
        last_attempt_at_jabvox: Time.current,
        uniqueid_jabvox: nil,
        linkedid_jabvox: nil,
        outcome_jabvox: nil
      )
      rec
    end
  rescue StandardError => e
    Rails.logger.error "[VoiceBroadcast] reserve_next_recipient failed | #{e.message}"
    nil
  end

  def originate(service, recipient, playback)
    # reserve_next_recipient devuelve :skip cuando salta un DNC; no marca.
    return if recipient == :skip

    result = service.originate(
      phone: recipient.phone_jabvox, broadcast: @broadcast,
      recipient: recipient, playback_ref: playback
    )
    return if result[:success]

    # Originate rechazado de inmediato: marcar fallido para que el reporte lo
    # cuente y no quede el destinatario pegado en 'calling'. El OriginateResponse
    # asíncrono (si llega) lo refinará vía el listener.
    recipient.update_columns(status_jabvox: 'failed', outcome_jabvox: 'failed') # rubocop:disable Rails/SkipsModelValidations
    @broadcast.increment!(:failed_count_jabvox) # rubocop:disable Rails/SkipsModelValidations
  end

  # ¿El número está en la lista de exclusión (DNC) de la cuenta? Reutiliza la
  # infraestructura de leads excluidos si existe; si no hay DNC configurada, false.
  def dnc_blocked?(phone)
    return false if phone.blank?
    return false unless @account.respond_to?(:jabvox_dnc_entries)

    digits = phone.to_s.gsub(/\D/, '')
    @account.jabvox_dnc_entries.exists?(phone_jabvox: digits)
  rescue StandardError
    false
  end

  def within_operating_window?
    @broadcast.in_schedule? &&
      Jabvox::VoiceBroadcast::OriginateService.new(@account.jabvox_voip_config).ami_reachable?
  rescue StandardError
    false
  end

  # Marca el broadcast como 'completed' cuando no quedan pendientes ni llamadas en
  # vuelo (todos los destinatarios tienen desenlace).
  def finish_if_done
    return unless @broadcast.remaining_recipients_count.zero? && @broadcast.in_flight_count.zero?

    @broadcast.update_columns(status_jabvox: 'completed', finished_at_jabvox: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info "[VoiceBroadcast] completed | broadcast=#{@broadcast.id}"
  end

  def tick_lock_key
    "jabvox_vb_tick_#{@broadcast.id}"
  end
end
