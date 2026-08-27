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

  # Devuelve el nº de llamadas originadas en este tick.
  def tick
    return 0 unless @broadcast.running?
    return 0 unless within_operating_window?

    result = Jabvox::RedisLock.with_lock(tick_lock_key, ttl: TICK_LOCK_TTL) do |lock|
      originated = dial_batch(lock)
      finish_if_done
      originated
    end
    result == Jabvox::RedisLock::NOT_ACQUIRED ? 0 : result
  end

  private

  # Cuántas llamadas nuevas caben AHORA = min(cupo de concurrencia, tope de CPS).
  def dial_batch(lock)
    slots = @broadcast.max_concurrent_jabvox - @broadcast.in_flight_count
    return 0 if slots <= 0

    budget = [slots, @broadcast.cps_jabvox].min
    config = @account.jabvox_voip_config
    return 0 if config&.host.blank?

    service = Jabvox::DialerService.new(config)
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
      rec = @broadcast.recipients
                      .where(status_jabvox: 'pending')
                      .order(:id).lock('FOR UPDATE SKIP LOCKED').first
      next nil if rec.nil?

      if dnc_blocked?(rec.phone_jabvox)
        # Número en DNC: se cierra como opt-out y NO se marca (el caller filtra :skip).
        rec.update_columns(status_jabvox: 'done', outcome_jabvox: 'opted_out') # rubocop:disable Rails/SkipsModelValidations
        next :skip
      end
      rec.update_columns( # rubocop:disable Rails/SkipsModelValidations
        status_jabvox: 'calling',
        attempts_jabvox: rec.attempts_jabvox.to_i + 1,
        last_attempt_at_jabvox: Time.current
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

    result = service.originate_voicebot(
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
    @broadcast.in_schedule? && Jabvox::DialerService.new(@account.jabvox_voip_config).ami_reachable?
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
