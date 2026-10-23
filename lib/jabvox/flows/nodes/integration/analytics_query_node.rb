# frozen_string_literal: true

# integration.analytics_query — consulta de SOLO LECTURA contra una fuente de datos
# externa conectada en Analytics (jabvox_analytics_data_sources) y devuelve las
# filas como colección (`rows`) para iterarlas con un bucle y, por ejemplo,
# mandarle un mensaje a cada contacto.
#
# Dos modos:
#   - 'sql'     : un SELECT libre (validado read-only + binds de {{marcadores}}).
#   - 'builder' : tabla + columnas + filtros + orden; el SELECT se genera seguro
#                 (identificadores saneados, operadores de allowlist, valores
#                 escapados). No hay SQL del usuario en este modo.
#
# Toda la seguridad vive en Jabvox::Flows::AnalyticsQueryService, que reutiliza la
# infraestructura blindada de Analytics: HostGuard (anti-SSRF), SqlValidator
# (defensa en profundidad) y el adapter read-only a nivel de servidor (BEGIN READ
# ONLY + statement_timeout + LIMIT forzado + cierre de conexión garantizado).
class Jabvox::Flows::Nodes::Integration::AnalyticsQueryNode < Jabvox::Flows::Nodes::Base
  type 'integration.analytics_query'
  label 'Consultar base de datos (Analytics)'
  items_path 'rows'

  def perform
    source_id = require_param!(:dataSourceId, 'la fuente de datos de Analytics')
    service = Jabvox::Flows::AnalyticsQueryService.new(
      account_id: ctx.account_id, data_source_id: source_id, limit: param(:limit)
    )

    result = mode == 'builder' ? run_builder(service) : run_sql(service)
    { 'rows' => result.rows, 'columns' => result.columns,
      'row_count' => result.row_count, 'elapsed_ms' => result.elapsed_ms }
  rescue Jabvox::Flows::AnalyticsQueryService::QueryError => e
    fail_with!(e.message)
  end

  private

  def mode
    param(:mode).to_s == 'builder' ? 'builder' : 'sql'
  end

  def run_sql(service)
    service.run_sql(raw_sql, params: placeholder_params)
  end

  # El SQL se lee CRUDO del nodo (sin pasar por el resolver de plantillas del
  # motor): sus `{{marcadores}}` son binds que resuelve AnalyticsQueryService como
  # parámetros ligados, no referencias del flujo. Si se tomara de los params ya
  # resueltos, el motor los habría vaciado ({{hoy}} -> "") y el bind se perdería.
  # Los VALORES de esos binds sí salen de sqlParams (resueltos), que pueden traer
  # {{trigger.*}} u otras referencias del flujo con normalidad.
  def raw_sql
    raw = node.params['sql'] || node.params[:sql]
    raw.to_s
  end

  def run_builder(service)
    service.run_builder(
      table: param(:table), columns: list_param(:columns),
      filters: array_param(:filters), order_by: param(:orderBy),
      order_dir: param(:orderDir)
    )
  end

  # Valores para los marcadores {{nombre}} del SQL. El usuario los define como pares
  # clave/valor; cada valor viaja como bind, nunca concatenado.
  def placeholder_params
    raw = param(:sqlParams)
    return {} unless raw.is_a?(Hash)

    raw
  end

  def require_param!(key, label)
    value = param(key)
    fail_with!("Falta #{label}: elige ese campo en el paso.") if value.to_s.strip.blank?
    value
  end

  def list_param(key)
    value = param(key)
    return value if value.is_a?(Array)

    value.to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def array_param(key)
    value = param(key)
    value.is_a?(Array) ? value : []
  end
end
