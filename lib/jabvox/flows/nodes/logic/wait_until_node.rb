# frozen_string_literal: true

# logic.wait_until — suspende el run hasta una fecha/hora concreta. Una fecha ya
# pasada NO suspende: continúa de inmediato en vez de quedar colgado para siempre.
class Jabvox::Flows::Nodes::Logic::WaitUntilNode < Jabvox::Flows::Nodes::Base
  type 'logic.wait_until'
  label 'Esperar hasta'

  def perform
    raw = param(:until).to_s.strip
    fail_with!('Falta la fecha hasta la que esperar.') if raw.blank?

    resume_at = parse_time(raw)
    fail_with!("Fecha inválida: '#{raw}'") if resume_at.nil?
    return already_passed(resume_at) if resume_at <= Time.current

    ok({ 'resumeAt' => resume_at.iso8601, 'waited' => true,
         'delayMs' => ((resume_at - Time.current) * 1000).round },
       wait: { 'reason' => 'wait_until', 'resumeAt' => resume_at })
  end

  private

  def parse_time(raw)
    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end

  def already_passed(resume_at)
    { 'resumeAt' => resume_at.iso8601, 'waited' => false,
      'reason' => 'La fecha ya había pasado: se continuó de inmediato.' }
  end
end
