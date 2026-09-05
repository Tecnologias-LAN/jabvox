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
  # TTL base del lock por broadcast; el heartbeat lo renueva mientras el tick
  # origina llamadas, así un tick lento (AMI) nunca deja expirar el lock a mitad
  # y no hay doble-marcación.
  TICK_LOCK_TTL = 20
  CPS_SLEEP = 0.05 # pausa mínima entre Originates dentro de un tick

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

  # Cuántas llamadas nuevas caben AHORA = min(cupo de concurrencia, tope de CPS).
  def dial_batch(lock)
    slots = @broadcast.max_concurrent_jabvox - @broadcast.in_flight_count
    return 0 if slots <= 0

    budget = [slots, @broadcast.cps_jabvox].min
    config = @account.jabvox_voip_config
    return 0 if config&.host.blank?

    service = Jabvox::VoiceBroadcast::OriginateService.new(config)
    playback = Jabvox::VoiceBroadcast::DeployService.playback_ref(@broadcast.audio_filename_jabvox)
    count = 0
    budget.times do
      # Fencing: si perdimos el lock (proceso congelado > TTL y otro tick lo tomó),
      # dejamos de originar para no doble-marcar con el nuevo dueño.
      break unless lock.held?

      recipient = reserve_next_recipient
      break if recipient.nil? # no quedan pendientes

      originate(service, recipient, playback)
      count += 1
      sleep CPS_SLEEP
    end
    count
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
