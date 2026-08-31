# frozen_string_literal: true

# logic.datetime — instante actual (con desplazamiento) descompuesto en una zona
# horaria IANA. En Rails la zona la resuelve ActiveSupport, sin Intl.
class Jabvox::Flows::Nodes::Logic::DatetimeNode < Jabvox::Flows::Nodes::Base
  type 'logic.datetime'
  label 'Fecha y hora actual'

  DEFAULT_TIMEZONE = 'America/Bogota'
  WEEKDAY_NAMES = %w[domingo lunes martes miércoles jueves viernes sábado].freeze

  def perform
    # Vacío = Bogotá, NO UTC: el '' del formulario se tomaba por zona inválida
    # y caía a UTC, cinco horas de desfase.
    requested = first_filled(param(:timezone), DEFAULT_TIMEZONE)
    zone = ActiveSupport::TimeZone[requested]
    instant = (zone || Time.find_zone!('UTC')).now + offset_seconds
    build_output(instant, requested, zone)
  end

  private

  def offset_seconds
    (int_or(param(:offsetDays), 0) * 86_400) + (int_or(param(:offsetHours), 0) * 3600) +
      (int_or(param(:offsetMinutes), 0) * 60)
  end

  def build_output(instant, requested, zone)
    parts = time_parts(instant)
    out = parts.merge('value' => formatted(parts), 'timezone' => zone ? zone.name : 'UTC')
    # Zona inválida: se documenta en la salida en vez de fallar.
    out['timezoneFallback'] = { 'requested' => requested, 'applied' => 'UTC' } if zone.nil?
    out
  end

  def time_parts(instant)
    date = instant.strftime('%Y-%m-%d')
    time = instant.strftime('%H:%M')
    { 'iso' => instant.iso8601, 'date' => date, 'time' => time, 'datetime' => "#{date} #{time}",
      'year' => instant.year, 'month' => instant.month, 'day' => instant.day,
      'hour' => instant.hour, 'minute' => instant.min, 'second' => instant.sec,
      'weekday' => instant.wday, 'weekdayName' => WEEKDAY_NAMES[instant.wday],
      'timestamp' => (instant.to_f * 1000).round, 'monthDay' => instant.strftime('%m-%d'),
      'offset' => instant.strftime('%:z') }
  end

  def formatted(parts)
    case first_filled(param(:format), 'iso')
    when 'date' then parts['date']
    when 'time' then parts['time']
    when 'datetime' then parts['datetime']
    when 'day_month' then format('%<d>02d-%<m>02d', d: parts['day'], m: parts['month'])
    when 'custom' then apply_custom(parts)
    else parts['iso']
    end
  end

  # Tokens YYYY YY MM DD HH mm ss en UN solo pase, para que no se solapen.
  def apply_custom(parts)
    pattern = first_filled(param(:customFormat), 'YYYY-MM-DD HH:mm')
    tokens = { 'YYYY' => parts['year'].to_s, 'YY' => format('%02d', parts['year'] % 100),
               'MM' => format('%02d', parts['month']), 'DD' => format('%02d', parts['day']),
               'HH' => format('%02d', parts['hour']), 'mm' => format('%02d', parts['minute']),
               'ss' => format('%02d', parts['second']) }
    pattern.gsub(/YYYY|YY|MM|DD|HH|mm|ss/) { tokens[Regexp.last_match(0)] }
  end
end
