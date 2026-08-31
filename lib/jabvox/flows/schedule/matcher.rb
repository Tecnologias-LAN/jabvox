# frozen_string_literal: true

# ¿Le toca disparar a esta configuración en el minuto actual? La comparación se
# hace SIEMPRE en la zona del nodo, que es la corrección que motivó la pieza.
module Jabvox::Flows::Schedule::Matcher
  module_function

  def fire?(config, now = Time.current)
    at = Jabvox::Flows::Schedule::Timezone.at(now, config.timezone)
    case config.mode
    when 'minutes' then minutes?(config, at)
    when 'hours' then hours?(config, at)
    when 'daily' then daily?(config, at)
    when 'weekly' then weekly?(config, at)
    when 'monthly' then monthly?(config, at)
    else false
    end
  end

  # Cadencias sub-diarias: no dependen de la zona salvo offsets de :30/:45, y
  # ahí la diferencia es irrelevante para "cada X minutos".
  def minutes?(config, at)
    (((at.hour * 60) + at.min) % config.every).zero?
  end

  def hours?(config, at)
    at.min.zero? && (at.hour % config.every).zero?
  end

  def daily?(config, at)
    return false unless hhmm(at) == config.time_hhmm
    return true if config.every <= 1

    (at.yday % config.every).zero?
  end

  def weekly?(config, at)
    hhmm(at) == config.time_hhmm && config.weekdays.include?(iso_weekday(at))
  end

  def monthly?(config, at)
    return false unless hhmm(at) == config.time_hhmm

    # Clamp: si el mes no tiene ese día, dispara el último día del mes.
    at.day == [config.day_of_month, at.end_of_month.day].min
  end

  def hhmm(at)
    format('%<h>02d:%<m>02d', h: at.hour, m: at.min)
  end

  # ISO: lunes = 1 … domingo = 7 (Ruby usa domingo = 0).
  def iso_weekday(at)
    at.wday.zero? ? 7 : at.wday
  end
end
