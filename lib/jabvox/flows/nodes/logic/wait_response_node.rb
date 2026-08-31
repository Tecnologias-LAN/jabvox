# frozen_string_literal: true

# logic.wait_response — suspende el run hasta que llegue una respuesta externa.
# Si vence el plazo sin respuesta, el run termina en fallo: "me respondieron" y
# "no me respondieron" no pueden ser indistinguibles.
class Jabvox::Flows::Nodes::Logic::WaitResponseNode < Jabvox::Flows::Nodes::Base
  type 'logic.wait_response'
  label 'Esperar respuesta'

  DEFAULT_TIMEOUT_MS = 86_400_000
  MAX_TIMEOUT_MS = 30 * 24 * 60 * 60 * 1000

  def perform
    # Un timeout inválido o <= 0 dejaría el run esperando sin vencimiento.
    raw = int_or(param(:timeoutMs), DEFAULT_TIMEOUT_MS)
    timeout_ms = raw.positive? ? [raw, MAX_TIMEOUT_MS].min : DEFAULT_TIMEOUT_MS
    resume_at = Time.current + (timeout_ms / 1000.0)

    ok({ 'awaiting' => true, 'timeoutMs' => timeout_ms, 'resumeAt' => resume_at.iso8601,
         'resumeWith' => "POST /api/v1/accounts/#{ctx.account_id}/jabvox/flow_runs/#{ctx.run_id}/resume" },
       wait: { 'reason' => 'wait_response', 'resumeAt' => resume_at })
  end
end
