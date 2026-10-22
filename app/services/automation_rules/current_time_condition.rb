# Jabvox: evaluacion de la condicion de franja horaria ("current_time") de las
# automations. No es un filtro SQL: compara la hora actual (en una zona fija)
# contra un rango { from, to } en formato 'HH:MM', soportando rangos que cruzan
# medianoche (ej. 18:30 -> 08:00 cubre toda la noche). Se incluye en
# AutomationRules::ConditionsFilterService.
module AutomationRules::CurrentTimeCondition
  # Zona horaria fija contra la que se compara la franja. Toda la operacion es de
  # un solo pais; si en el futuro se vuelve multi-zona, esto deberia salir de la
  # config de la cuenta/inbox.
  CURRENT_TIME_ZONE = 'America/Bogota'.freeze

  def current_time_attribute?(query_hash)
    query_hash['attribute_key'] == 'current_time'
  end

  # True solo cuando la condicion es de hora Y se cumple (para saltarla en el loop
  # sin tocar el SQL). Si es de hora pero no se cumple, devuelve false y el loop
  # corta la regla via current_time_attribute?.
  def current_time_condition?(query_hash)
    current_time_attribute?(query_hash) && current_time_condition_met?(query_hash)
  end

  def current_time_condition_met?(query_hash)
    values = query_hash['values'] || {}
    from = parse_minutes(values['from'])
    to = parse_minutes(values['to'])
    return false if from.nil? || to.nil?

    now = Time.current.in_time_zone(CURRENT_TIME_ZONE)
    in_range = minutes_in_range?((now.hour * 60) + now.min, from, to)

    query_hash['filter_operator'] == 'is_not_between' ? !in_range : in_range
  end

  # True si `current` (minutos desde medianoche) cae en [from, to). Soporta rangos
  # que cruzan medianoche: si from > to, el rango es [from, 24:00) U [00:00, to).
  def minutes_in_range?(current, from, to)
    return current >= from && current < to if from <= to

    current >= from || current < to
  end

  # 'HH:MM' -> minutos desde medianoche. Devuelve nil si el formato es invalido.
  def parse_minutes(str)
    return nil if str.blank?

    h, m = str.to_s.split(':').map(&:to_i)
    return nil unless h&.between?(0, 23) && m&.between?(0, 59)

    (h * 60) + m
  end
end
