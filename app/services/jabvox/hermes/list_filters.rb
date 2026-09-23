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
