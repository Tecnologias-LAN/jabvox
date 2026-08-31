# frozen_string_literal: true

# logic.delay — pausa el flujo. Una espera corta se resuelve en el sitio; una
# larga SUSPENDE el run para no ocupar un slot del worker mientras espera.
class Jabvox::Flows::Nodes::Logic::DelayNode < Jabvox::Flows::Nodes::Base
  type 'logic.delay'
  label 'Esperar'

  SYNC_THRESHOLD_MS = 5_000
  MAX_DELAY_MS = 30 * 24 * 60 * 60 * 1000

  def perform
    raw = param(:ms)
    fail_with!("Milisegundos inválidos: '#{raw}'") unless valid_number?(raw)

    ms = int_or(raw, 0, min: 0, max: MAX_DELAY_MS)
    return suspend(ms) if ms > SYNC_THRESHOLD_MS

    sleep(ms / 1000.0)
    { 'waited' => true, 'ms' => ms, 'mode' => 'sync' }
  end

  private

  def valid_number?(raw)
    return false if blank_param?(raw)

    Float(raw.to_s).finite?
  rescue ArgumentError, TypeError
    false
  end

  def suspend(millis)
    resume_at = Time.current + (millis / 1000.0)
    ok({ 'waited' => false, 'ms' => millis, 'mode' => 'suspended', 'resumeAt' => resume_at.iso8601 },
       wait: { 'reason' => 'delay', 'resumeAt' => resume_at })
  end
end
