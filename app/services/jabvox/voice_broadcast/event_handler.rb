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
# Se le pasa el AMI listener para reutilizar su channel_var (lee la variable del
# canal con cache/Getvar, misma vía que el dialer).
class Jabvox::VoiceBroadcast::EventHandler
  def initialize(account_id, listener)
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
    when 'hangup'           then handle_hangup(recipient, event)
    end
  end

  private

  # Ancla al destinatario por el marcador del canal o el ActionID. account-scoped.
  def resolve_recipient(event)
    rid = channel_var(event, 'JABVOX_VB_RECIPIENT_ID')
    rid = rid.presence || recipient_id_from_action_id(event['actionid'])
    return nil if rid.blank?

    JabvoxVoiceBroadcastRecipient.find_by(id: rid.to_i, account_id: @account_id)
  end

  def recipient_id_from_action_id(action_id)
    m = action_id.to_s.match(/\Ajabvoxvb-(\d+)\z/)
    m && m[1]
  end

  def channel_var(event, var)
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
    return if recipient.played_full_jabvox # idempotente

    recipient.update_columns(played_full_jabvox: true) # rubocop:disable Rails/SkipsModelValidations
    increment_broadcast(recipient, :played_complete_count_jabvox)
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

  # OriginateResponse Failure: la llamada nunca se estableció → outcome según causa.
  def handle_originate_response(recipient, event)
    return if event['response'].to_s.casecmp?('Success')
    return unless recipient.status_jabvox == 'calling'

    outcome = originate_failure_outcome(event['reason'].to_s)
    finalize(recipient, outcome: outcome, status: retry_or_fail(recipient, outcome))
    increment_broadcast(recipient, :failed_count_jabvox) if outcome == 'failed'
  end

  # Hangup: cierra el destinatario si aún estaba 'calling'. answered_human si hubo
  # conversación (billsec>0 o AMD=HUMAN); si no, no_answer.
  def handle_hangup(recipient, event)
    return unless recipient.status_jabvox == 'calling'

    answered = event['billableseconds'].to_i.positive? || recipient.amd_status_jabvox == 'HUMAN'
    outcome = answered ? 'answered_human' : hangup_no_answer_outcome(event)
    stamp_uniqueid(recipient, event)
    finalize(recipient, outcome: outcome, status: retry_or_fail(recipient, outcome))
    increment_broadcast(recipient, :answered_human_count_jabvox) if outcome == 'answered_human'
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  def finalize(recipient, outcome:, status:)
    attrs = { outcome_jabvox: outcome, status_jabvox: status }
    recipient.update_columns(attrs) # rubocop:disable Rails/SkipsModelValidations
    # Contador de marcados: sube una sola vez cuando el destinatario deja 'calling'.
    increment_broadcast(recipient, :dialed_count_jabvox)
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

  def originate_failure_outcome(reason)
    case reason
    when '3', '5' then 'congestion' # circuit congestion / busy-ish
    when '8'      then 'no_answer'
    else 'failed'
    end
  end

  def hangup_no_answer_outcome(event)
    case event['cause'].to_s
    when '17' then 'busy'
    when '34', '42' then 'congestion'
    else 'no_answer'
    end
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
