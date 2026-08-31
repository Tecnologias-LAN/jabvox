# frozen_string_literal: true

# Descriptor de la espera que devuelve un handler en `NodeResult#wait`.
# Normaliza lo que llega del nodo (motivo + instante) a la forma que persiste el
# run, sin que el motor tenga que conocer ningún tipo de nodo concreto.
module Jabvox::Flows::Engine::WaitDescriptor
  # Motivos soportados. Solo `wait_response` se reanuda por una respuesta real;
  # los demás se reanudan al vencer el plazo.
  REASONS = %w[delay wait_until wait_response].freeze
  DEFAULT_REASON = 'delay'

  module_function

  # Devuelve { 'reason' => String, 'resumeAt' => Time|nil }.
  def normalize(wait)
    raw = wait.is_a?(Hash) ? wait.stringify_keys : {}
    { 'reason' => reason_of(raw), 'resumeAt' => time_of(raw['resumeAt'] || raw['resume_at']) }
  end

  def reason_of(raw)
    reason = raw['reason'].to_s
    REASONS.include?(reason) ? reason : DEFAULT_REASON
  end

  # Un instante ilegible NO suspende con plazo: el run queda esperando una
  # respuesta explícita en vez de despertar en un momento arbitrario.
  def time_of(value)
    case value
    when Time, DateTime then value.to_time
    when ActiveSupport::TimeWithZone then value
    when Numeric then Time.zone.at(value)
    when String then parse_time(value)
    end
  end

  def parse_time(value)
    Time.zone.parse(value)
  rescue ArgumentError, TypeError
    nil
  end

  # ¿La espera se resuelve por una RESPUESTA y no por el mero vencimiento?
  def response?(reason)
    reason.to_s == 'wait_response'
  end
end
