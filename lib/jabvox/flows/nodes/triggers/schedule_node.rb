# frozen_string_literal: true

# trigger.schedule — dispara de forma recurrente. `due?` decide si al instante
# dado toca disparar; la zona horaria vacía significa hora del SERVIDOR, que es
# lo que hacían los flujos guardados antes de existir el campo.
class Jabvox::Flows::Nodes::Triggers::ScheduleNode
  TYPE = 'trigger.schedule'
  LABEL = 'Programado'
  MODES = %w[minutes hours daily weekly monthly].freeze

  def self.register_on(registry)
    registry.register(TYPE, label: LABEL)
  end

  # ¿Toca disparar en `now`? `last_run_at` evita repetir dentro de la misma
  # ventana: sin él un barrido cada minuto dispararía varias veces la misma hora.
  def self.due?(node, now: Time.current, last_run_at: nil)
    config = config_of(node)
    local = in_zone(now, config[:timezone])
    case config[:mode]
    when 'minutes' then elapsed?(now, last_run_at, config[:every] * 60)
    when 'hours' then elapsed?(now, last_run_at, config[:every] * 3600)
    when 'weekly' then weekly_due?(config, local, last_run_at)
    when 'monthly' then monthly_due?(config, local, last_run_at)
    else daily_due?(config, local, last_run_at)
    end
  end

  def self.config_of(node)
    params = node.respond_to?(:params) && node.params.is_a?(Hash) ? node.params : {}
    mode = params['mode'].to_s.strip
    { mode: MODES.include?(mode) ? mode : 'daily',
      every: [Jabvox::Flows::Nodes::Params.int_or(params['every'], 1), 1].max,
      time: parse_time_of_day(params['time']),
      timezone: params['timezone'].to_s.strip,
      weekdays: weekdays_of(params['weekdays']),
      day_of_month: Jabvox::Flows::Nodes::Params.int_or(params['dayOfMonth'], 1, min: 1, max: 31) }
  end

  # 'HH:mm' → [hora, minuto]. Un valor ilegible cae a las 08:00, el defecto.
  def self.parse_time_of_day(raw)
    match = raw.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
    return [8, 0] if match.nil?

    [match[1].to_i.clamp(0, 23), match[2].to_i.clamp(0, 59)]
  end

  # 1 = lunes … 7 = domingo (ISO), como el catálogo.
  def self.weekdays_of(raw)
    list = (raw.is_a?(Array) ? raw : raw.to_s.split(',')).filter_map do |v|
      n = v.to_s.strip.to_i
      n if n.between?(1, 7)
    end
    list.presence || [1, 2, 3, 4, 5]
  end

  def self.in_zone(now, timezone)
    zone = timezone.present? ? ActiveSupport::TimeZone[timezone] : nil
    zone ? now.in_time_zone(zone) : now
  end

  def self.elapsed?(now, last_run_at, seconds)
    last_run_at.nil? || (now - last_run_at) >= seconds
  end

  # La hora de disparo ya pasó hoy y no se ha disparado dentro de esa ventana.
  def self.at_or_past_time?(config, local)
    hour, minute = config[:time]
    (local.hour * 60) + local.min >= (hour * 60) + minute
  end

  def self.already_ran_today?(config, local, last_run_at)
    return false if last_run_at.nil?

    in_zone(last_run_at, config[:timezone]).to_date == local.to_date
  end

  def self.daily_due?(config, local, last_run_at)
    return false unless at_or_past_time?(config, local)
    return false if already_ran_today?(config, local, last_run_at)
    # "Cada N días" se cuenta desde el último disparo, no desde el calendario.
    return true if last_run_at.nil? || config[:every] <= 1

    (local.to_date - in_zone(last_run_at, config[:timezone]).to_date).to_i >= config[:every]
  end

  def self.weekly_due?(config, local, last_run_at)
    return false unless config[:weekdays].include?(local.strftime('%u').to_i)

    at_or_past_time?(config, local) && !already_ran_today?(config, local, last_run_at)
  end

  # Si el mes no tiene ese día, se dispara el ÚLTIMO día del mes.
  def self.monthly_due?(config, local, last_run_at)
    target = [config[:day_of_month], local.end_of_month.day].min
    return false unless local.day == target

    at_or_past_time?(config, local) && !already_ran_today?(config, local, last_run_at)
  end
end
