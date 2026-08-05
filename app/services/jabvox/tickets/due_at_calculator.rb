# Calcula el vencimiento (due_at) de un ticket sumando los minutos del SLA sobre el
# calendario laboral de la cuenta gestora, no en tiempo corrido. Si no hay horario
# laboral configurado, cae a 24/7 lineal (from + minutos).
#
# business_hours (jsonb en la config del helpdesk):
#   { "enabled": true,
#     "days": [1,2,3,4,5],            # 0=domingo .. 6=sábado
#     "start_minute": 540,            # 09:00 en minutos desde medianoche
#     "end_minute": 1080,             # 18:00
#     "time_zone": "America/Bogota" }
class Jabvox::Tickets::DueAtCalculator
  MAX_ITERATIONS = 3660 # tope de seguridad (~10 años de días laborales)

  def initialize(sla_minutes, from: nil, config: nil)
    @sla_minutes = sla_minutes.to_i
    @from = from || Time.current
    @config = config || JabvoxTicketHelpdeskConfig.current
  end

  def call
    return @from + @sla_minutes.minutes unless business_hours_enabled?

    add_business_minutes
  end

  private

  def business_hours_enabled?
    bh.present? && bh['enabled'] && working_days.any? &&
      day_start_minute < day_end_minute
  end

  def bh
    @bh ||= @config&.business_hours_jabvox || {}
  end

  def working_days
    @working_days ||= Array(bh['days']).map(&:to_i)
  end

  def day_start_minute
    @day_start_minute ||= (bh['start_minute'] || 540).to_i
  end

  def day_end_minute
    @day_end_minute ||= (bh['end_minute'] || 1080).to_i
  end

  def zone
    @zone ||= ActiveSupport::TimeZone[bh['time_zone'] || 'UTC'] || ActiveSupport::TimeZone['UTC']
  end

  # Avanza `@sla_minutes` minutos laborales desde @from, saltando fuera de horario.
  def add_business_minutes
    cursor = zone.at(@from)
    remaining = @sla_minutes
    iterations = 0

    while remaining.positive? && iterations < MAX_ITERATIONS
      iterations += 1
      cursor = next_working_moment(cursor)
      available = minutes_until_day_end(cursor)
      step = [available, remaining].min
      cursor += step.minutes
      remaining -= step
    end
    cursor.utc
  end

  # Lleva el cursor al próximo instante dentro de horario laboral.
  def next_working_moment(cursor)
    cursor = advance_to_working_day(cursor)
    minute_of_day = (cursor.hour * 60) + cursor.min

    if minute_of_day < day_start_minute
      cursor.change(hour: 0, min: 0) + day_start_minute.minutes
    elsif minute_of_day >= day_end_minute
      advance_to_working_day(cursor.tomorrow.change(hour: 0, min: 0)) + day_start_minute.minutes
    else
      cursor
    end
  end

  def advance_to_working_day(cursor)
    cursor += 1.day until working_days.include?(cursor.wday)
    cursor
  end

  def minutes_until_day_end(cursor)
    minute_of_day = (cursor.hour * 60) + cursor.min
    day_end_minute - minute_of_day
  end
end
