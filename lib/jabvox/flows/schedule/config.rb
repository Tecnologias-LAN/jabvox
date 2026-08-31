# frozen_string_literal: true

# Configuración de un `trigger.schedule`, saneada. Todo valor ilegible degrada a
# un default razonable: un dedazo en UN flujo no puede tumbar el barrido de todos.
class Jabvox::Flows::Schedule::Config
  MODES = %w[minutes hours daily weekly monthly].freeze
  DEFAULT_MODE = 'daily'
  DEFAULT_TIME = '08:00'
  TIME_FORMAT = /\A([01]?\d|2[0-3]):[0-5]\d\z/

  attr_reader :mode, :every, :time, :weekdays, :day_of_month, :timezone

  def self.from_params(params)
    new(params.is_a?(Hash) ? params.stringify_keys : {})
  end

  def initialize(params)
    @mode = MODES.include?(params['mode'].to_s) ? params['mode'].to_s : DEFAULT_MODE
    @every = positive_int(params['every'], 1)
    @time = TIME_FORMAT.match?(params['time'].to_s) ? params['time'].to_s : DEFAULT_TIME
    @weekdays = Array(params['weekdays']).filter_map { |d| d.to_i if (1..7).cover?(d.to_i) }
    @day_of_month = clamp_day(params['dayOfMonth'])
    @timezone = Jabvox::Flows::Schedule::Timezone.resolve(params['timezone'])
  end

  # Hora del usuario normalizada a 'HH:MM' para comparar con el reloj.
  def time_hhmm
    hour, minute = @time.split(':')
    format('%<h>02d:%<m>02d', h: hour.to_i, m: minute.to_i)
  end

  private

  def positive_int(value, fallback)
    number = value.to_i
    number >= 1 ? number : fallback
  end

  def clamp_day(value)
    day = value.to_i
    (1..31).cover?(day) ? day : 1
  end
end
