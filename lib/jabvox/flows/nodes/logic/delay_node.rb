# frozen_string_literal: true

# logic.delay — pausa el flujo. Una espera corta se resuelve en el sitio; una
# larga SUSPENDE el run para no ocupar un slot del worker mientras espera.
class Jabvox::Flows::Nodes::Logic::DelayNode < Jabvox::Flows::Nodes::Base
  type 'logic.delay'
  label 'Esperar'

  # Por ENCIMA de este umbral la espera SUSPENDE el run (libera el worker). Por
  # debajo se duerme en el sitio: un sleep de hasta 1 s no justifica el coste de
  # suspender y reanudar. Antes el umbral era 5 s, lo que podía retener un slot de
  # Sidekiq 5 s por nodo y, con muchos runs, congestionar la cola `jabvox_flows`.
  SYNC_THRESHOLD_MS = 1_000
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
