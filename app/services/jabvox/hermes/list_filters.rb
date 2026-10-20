# frozen_string_literal: true

# Filtros comunes de los handlers de listado de Hermes.
#
# Muchos `list_*` nacieron ignorando sus parámetros (`def list_x(_params)`), así que
# devolvían SIEMPRE la colección entera recortada a MAX_ROWS. Eso rompía dos cosas para el
# agente: pedir "las tareas del tablero X" traía las de todos los tableros, y pedir
# "el reporte del último mes" era imposible porque no había forma de acotar por fecha.
#
# Aquí vive esa lógica una sola vez para que cada handler solo declare QUÉ acepta.
module Jabvox::Hermes::ListFilters
  # Tope duro de filas que puede pedir el agente, para que un `limit` alto no se convierta en
  # un volcado de la tabla.
  def capped_limit(params, default: nil)
    max = Jabvox::Hermes::ServiceLayer::MAX_ROWS
    requested = params[:limit].presence&.to_i
    return default || max if requested.nil? || requested <= 0

    [requested, max].min
  end

  # Acota por rango de fechas. `since`/`until` son ISO (2026-08-01, o con hora); una fecha
  # inválida se ignora en vez de reventar la consulta, porque viene de texto libre del LLM.
  #
  # `until` es INCLUSIVO cuando solo trae fecha: "until 2026-08-31" cubre ese día entero, que
  # es lo que espera quien pregunta "del 1 al 31 de agosto".
  def filter_by_date(scope, params, column: :created_at)
    since = parse_time(params[:since])
    till  = parse_time(params[:until], end_of_day: true)
    return scope if since.nil? && till.nil?

    # `column` lo fija SIEMPRE el handler, nunca el LLM, pero se valida contra las columnas
    # reales de la tabla antes de interpolarla: así una columna inventada es un error claro
    # aquí y no SQL arbitrario si alguien la expusiera a params en el futuro.
    col = scope.klass.column_names.include?(column.to_s) ? column.to_s : nil
    raise ArgumentError, "columna de fecha inválida: #{column}" if col.nil?

    quoted = "#{scope.quoted_table_name}.#{scope.connection.quote_column_name(col)}"
    scope = scope.where("#{quoted} >= ?", since) if since
    scope = scope.where("#{quoted} <= ?", till) if till
    scope
  end

  # Aplica `where(col => valor)` solo para los parámetros presentes: un filtro que el agente
  # no mandó no debe restringir nada.
  def filter_by(scope, params, *keys)
    columns = scope.klass.column_names
    keys.each do |key|
      value = params[key]
      next if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      # Un nombre que no sea columna real se ignora en vez de llegar a la consulta.
      next unless columns.include?(key.to_s)

      scope = scope.where(key => value)
    end
    scope
  end

  # Resuelve un umbral de tiempo relativo "hace N" a un Time absoluto en el pasado.
  # El LLM suele preguntar "los que no responden hace 5 horas / 30 minutos / 2 días" sin
  # calcular la fecha. Acepta un número + unidad por params (last_minutes/last_hours/last_days)
  # y devuelve el instante contra el que comparar (Time.current - duración), o nil si no se pidió.
  # Se topa a 90 días para que un valor disparatado no barra toda la tabla.
  def relative_threshold(params)
    minutes = params[:last_minutes].to_i
    hours   = params[:last_hours].to_i
    days    = params[:last_days].to_i
    total_minutes = minutes + (hours * 60) + (days * 24 * 60)
    return nil unless total_minutes.positive?

    total_minutes = [total_minutes, 90 * 24 * 60].min
    Time.current - total_minutes.minutes
  end

  # Rango efectivo [desde, hasta] combinando umbral relativo y fechas absolutas, en este orden:
  # si hay relativo (last_*), desde = ahora - duración y hasta = ahora; si no, usa since/until ISO.
  # Devuelve [nil, nil] si no se pidió nada (sin filtro). Lo usan las tools por agente/reportes
  # para aceptar indistintamente "últimos 7 días" o "del 1 al 15".
  def effective_range(params)
    rel = relative_threshold(params)
    return [rel, Time.current] if rel

    [parse_time(params[:since]), parse_time(params[:until], end_of_day: true)]
  end

  # Aplica effective_range a un scope sobre la columna dada (validada contra la tabla).
  def filter_by_effective_range(scope, params, column: :created_at)
    from, to = effective_range(params)
    return scope if from.nil? && to.nil?

    col = scope.klass.column_names.include?(column.to_s) ? column.to_s : nil
    raise ArgumentError, "columna de fecha inválida: #{column}" if col.nil?

    quoted = "#{scope.quoted_table_name}.#{scope.connection.quote_column_name(col)}"
    scope = scope.where("#{quoted} >= ?", from) if from
    scope = scope.where("#{quoted} <= ?", to) if to
    scope
  end

  private

  def parse_time(value, end_of_day: false)
    raw = value.to_s.strip
    return nil if raw.empty?

    time = Time.zone.parse(raw)
    return nil if time.nil?
    # Solo fecha (sin hora) y es el extremo superior: se extiende al final del día.
    return time.end_of_day if end_of_day && raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    time
  rescue ArgumentError, TypeError
    nil
  end
end
