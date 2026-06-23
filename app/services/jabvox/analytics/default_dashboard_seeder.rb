# Crea los dashboards predeterminados del módulo Analytics ("Autogestión" y "Valiosas").
#
# Traducción del seeder TypeScript (bi-seeder.service.ts, sistema NestJS externo) a los modelos de Jabvox.
# Cada widget usa SQL MySQL crudo en custom_sql_jabvox (no el builder visual), porque el motor de
# Jabvox para KPIs solo toma el último valor de la primera fila: los porcentajes computados (% Gestión,
# Presupuesto %, Participación) ya vienen calculados como una sola columna `valor` en el SQL.
#
# Helpers de agregado traducidos desde el TS:
#   COUNT                 -> COUNT(col)
#   COUNT_IF_GT_ZERO(col) -> SUM(CASE WHEN col > 0 THEN 1 ELSE 0 END)
#   COUNT_DISTINCT(col)   -> COUNT(DISTINCT col)
#   SUM                   -> SUM(col)
#   SUM_NUM(col)          -> SUM(CAST(col AS DECIMAL(18,2)))   (castea varchar a número)
#   computed ratio {num, den, scale:100} -> ROUND(num / NULLIF(den, 0) * scale, 2) AS valor
#
# La tabla principal (sourceTable) se aliasa como `t`, igual que el TS (las subconsultas correlacionadas
# referencian `t.name`). El puente lk_facturacion -> leads_cstm (vía lk_facturacion_leads_c, alias flc/lc)
# se incluye en los widgets de lk_facturacion para que los filtros de departamento/segmento/mg apliquen
# (es 1:1, no infla los conteos).
#
# Diferencia Autogestión vs Valiosas (derivación del ciclo de gestión):
#   - Autogestión: la llamada se enlaza al NE por calls.parent_id (parent_type='Leads') y el ciclo se
#     toma de calls_cstm.ciclo_gestion_c.
#   - Valiosas: ciclo_gestion_c está vacío; el ciclo se deriva de DATE_FORMAT(calls.date_start,'%Y%m')
#     y el lead se enlaza por calls_leads.
#
# Uso: Jabvox::Analytics::DefaultDashboardSeeder.new(account: account, user: user).call
class Jabvox::Analytics::DefaultDashboardSeeder
  AUTOGESTION_DB = 'CRM_Autogestion'.freeze
  VALIOSAS_DB = 'CRM_Valiosas'.freeze

  def initialize(account:, user: nil)
    @account = account
    @user = user
  end

  # Idempotente: si ya existe un dashboard con el name_jabvox objetivo en la cuenta, lo salta
  # (no recrea ni destruye datos). Devuelve los dashboards (creados o existentes).
  def call
    [build_autogestion, build_valiosas]
  end

  private

  attr_reader :account, :user

  # ────────────────────────────────────────────────────────────────────────────────────────
  # Autogestión
  # ────────────────────────────────────────────────────────────────────────────────────────
  def build_autogestion
    existing = account.jabvox_analytics_dashboards.find_by(name_jabvox: 'Autogestión')
    return existing if existing

    folder = find_or_create_folder('Autogestión')
    ds_id = data_source_id_for(AUTOGESTION_DB)

    dashboard = account.jabvox_analytics_dashboards.create!(
      name_jabvox: 'Autogestión',
      description_jabvox: 'Dashboard de autogestión: NE, gestión, presupuesto, producción e interacciones por ciclo',
      folder_id: folder.id,
      created_by_id: user&.id,
      global_filters_jabvox: {},
      cache_ttl_seconds_jabvox: 300,
      layout_jabvox: autogestion_layout
    )

    autogestion_widgets.each_with_index do |w, idx|
      dashboard.widgets.create!(
        account_id: account.id,
        data_source_id: ds_id,
        widget_type_jabvox: w[:type],
        title_jabvox: w[:title],
        position_jabvox: idx,
        custom_sql_jabvox: w[:sql],
        query_spec_jabvox: {},
        config_jabvox: {}
      )
    end

    dashboard
  end

  # layout_jabvox: [{i: widget_index, x, y, w, h}] derivado de gridX/gridY/gridW/gridH del TS.
  def autogestion_layout
    [
      { i: 0, x: 0,  y: 0,  w: 3,  h: 3 },  # NE
      { i: 1, x: 3,  y: 0,  w: 3,  h: 3 },  # % Gestión
      { i: 2, x: 6,  y: 0,  w: 3,  h: 3 },  # Presupuesto
      { i: 3, x: 9,  y: 0,  w: 3,  h: 3 },  # Participación de Pedidos
      { i: 4, x: 0,  y: 3,  w: 8,  h: 8 },  # Venta sin IVA vs Presupuesto
      { i: 5, x: 8,  y: 3,  w: 8,  h: 8 },  # NE con Pedido vs Meta
      { i: 6, x: 16, y: 3,  w: 8,  h: 8 },  # NE Total vs NE con Pedido
      { i: 7, x: 0,  y: 11, w: 24, h: 7 },  # Interacciones por Ciclo
      { i: 8, x: 0,  y: 16, w: 24, h: 9 },  # Resumen Histórico
      { i: 9, x: 0,  y: 24, w: 24, h: 8 }   # Gestiones por Ciclo
    ]
  end

  def autogestion_widgets
    [
      # Widget 0 — NE: total de filas en lk_facturacion (una por NE por ciclo).
      {
        title: 'NE', type: 'number',
        sql: <<~SQL
          SELECT COUNT(t.id) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 1 — % Gestión = NEs con facturación / NE total * 100.
      {
        title: '% Gestión', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(t.id), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 2 — Presupuesto % = SUM(facturacion) / SUM(presupuesto_c) * 100.
      {
        title: 'Presupuesto', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(t.facturacion)
                   / NULLIF(SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 3 — Participación de Pedidos = NEs con pedido / NE total * 100.
      {
        title: 'Participación de Pedidos', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(t.id), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 4 — Venta sin IVA vs Presupuesto por ciclo.
      {
        title: 'Venta sin IVA vs Presupuesto', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 SUM(t.facturacion) AS venta_sin_iva,
                 SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))) AS presupuesto
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 5 — NE con Pedido vs Meta por ciclo.
      {
        title: 'NE con Pedido vs Meta', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido,
                 SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))) AS meta_pedidos
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 6 — NE Total vs NE con Pedido por ciclo.
      {
        title: 'NE Total vs NE con Pedido', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 COUNT(t.id) AS ne_total,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 7 — Interacciones por Ciclo (Autogestión: ciclo vía calls_cstm.ciclo_gestion_c,
      # lead vía calls.parent_id con parent_type='Leads').
      {
        title: 'Interacciones por Ciclo', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 (SELECT COUNT(DISTINCT ca2.parent_id)
                  FROM calls ca2
                  JOIN calls_cstm cc2 ON ca2.id = cc2.id_c
                  WHERE CAST(cc2.ciclo_gestion_c AS CHAR) = CAST(t.name AS CHAR)
                    AND ca2.parent_type = 'Leads'
                    AND ca2.deleted = 0) AS ne_gestionados,
                 (SELECT COUNT(ca3.id)
                  FROM calls ca3
                  JOIN calls_cstm cc3 ON ca3.id = cc3.id_c
                  WHERE CAST(cc3.ciclo_gestion_c AS CHAR) = CAST(t.name AS CHAR)
                    AND ca3.deleted = 0) AS interacciones
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 8 — Resumen Histórico (tabla). Las columnas computadas del TS (% Efectividad,
      # Cumplimiento frecuencia/presupuesto, Orden promedio, % NE) se calculan aquí en SQL.
      {
        title: 'Resumen Histórico', type: 'table',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 COUNT(t.id) AS ne,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido,
                 ROUND(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                       / NULLIF(COUNT(t.id), 0) * 100, 2) AS pct_efectividad,
                 SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))) AS meta_pedidos,
                 ROUND(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))), 0) * 100, 2) AS cumplimiento_frecuencia,
                 SUM(t.facturacion) AS venta_sin_iva,
                 SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))) AS presupuesto,
                 ROUND(SUM(t.facturacion)
                       / NULLIF(SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))), 0) * 100, 2) AS cumplimiento_presupuesto,
                 ROUND(SUM(t.facturacion)
                       / NULLIF(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END), 0), 2) AS orden_promedio,
                 (SELECT COUNT(DISTINCT ca2.parent_id)
                  FROM calls ca2
                  JOIN calls_cstm cc2 ON ca2.id = cc2.id_c
                  WHERE CAST(cc2.ciclo_gestion_c AS CHAR) = CAST(t.name AS CHAR)
                    AND ca2.parent_type = 'Leads'
                    AND ca2.deleted = 0) AS ne_gestionados,
                 ROUND(
                   (SELECT COUNT(DISTINCT ca2.parent_id)
                    FROM calls ca2
                    JOIN calls_cstm cc2 ON ca2.id = cc2.id_c
                    WHERE CAST(cc2.ciclo_gestion_c AS CHAR) = CAST(t.name AS CHAR)
                      AND ca2.parent_type = 'Leads'
                      AND ca2.deleted = 0)
                   / NULLIF(COUNT(t.id), 0) * 100, 2) AS pct_ne,
                 (SELECT COUNT(ca3.id)
                  FROM calls ca3
                  JOIN calls_cstm cc3 ON ca3.id = cc3.id_c
                  WHERE CAST(cc3.ciclo_gestion_c AS CHAR) = CAST(t.name AS CHAR)
                    AND ca3.deleted = 0) AS interacciones
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name DESC
          LIMIT 50
        SQL
      },
      # Widget 9 — Gestiones por Ciclo (tabla): una fila por ciclo_gestion_c con su conteo de
      # gestiones (llamadas) y NEs gestionados (leads únicos vía calls.parent_id).
      {
        title: 'Gestiones por Ciclo', type: 'table',
        sql: <<~SQL
          SELECT cc.ciclo_gestion_c AS ciclo,
                 COUNT(t.id) AS gestiones,
                 COUNT(DISTINCT t.parent_id) AS ne_gestionados
          FROM calls t
          LEFT JOIN calls_cstm cc ON t.id = cc.id_c
          WHERE t.deleted = 0
            AND t.parent_type = 'Leads'
            AND cc.ciclo_gestion_c IS NOT NULL
          GROUP BY cc.ciclo_gestion_c
          ORDER BY cc.ciclo_gestion_c DESC
          LIMIT 100
        SQL
      }
    ]
  end

  # ────────────────────────────────────────────────────────────────────────────────────────
  # Valiosas
  # ────────────────────────────────────────────────────────────────────────────────────────
  def build_valiosas
    existing = account.jabvox_analytics_dashboards.find_by(name_jabvox: 'Valiosas')
    return existing if existing

    folder = find_or_create_folder('Valiosas')
    ds_id = data_source_id_for(VALIOSAS_DB)

    dashboard = account.jabvox_analytics_dashboards.create!(
      name_jabvox: 'Valiosas',
      description_jabvox: 'Dashboard CRM Valiosas: NE, gestión, presupuesto, producción e interacciones por ciclo',
      folder_id: folder.id,
      created_by_id: user&.id,
      global_filters_jabvox: {},
      cache_ttl_seconds_jabvox: 300,
      layout_jabvox: valiosas_layout
    )

    valiosas_widgets.each_with_index do |w, idx|
      dashboard.widgets.create!(
        account_id: account.id,
        data_source_id: ds_id,
        widget_type_jabvox: w[:type],
        title_jabvox: w[:title],
        position_jabvox: idx,
        custom_sql_jabvox: w[:sql],
        query_spec_jabvox: {},
        config_jabvox: {}
      )
    end

    dashboard
  end

  def valiosas_layout
    [
      { i: 0, x: 0,  y: 0,  w: 3,  h: 3 },  # NE
      { i: 1, x: 3,  y: 0,  w: 3,  h: 3 },  # % Gestión
      { i: 2, x: 6,  y: 0,  w: 3,  h: 3 },  # Presupuesto
      { i: 3, x: 9,  y: 0,  w: 3,  h: 3 },  # Participación de Pedidos
      { i: 4, x: 0,  y: 3,  w: 8,  h: 8 },  # Venta sin IVA vs Presupuesto
      { i: 5, x: 8,  y: 3,  w: 8,  h: 8 },  # NE con Pedido vs Meta
      { i: 6, x: 16, y: 3,  w: 8,  h: 8 },  # NE Total vs NE con Pedido
      { i: 7, x: 0,  y: 11, w: 24, h: 7 },  # Interacciones por Ciclo
      { i: 8, x: 0,  y: 18, w: 24, h: 9 },  # Resumen Histórico
      { i: 9, x: 0,  y: 27, w: 24, h: 8 }   # Frecuencia por Ciclo
    ]
  end

  def valiosas_widgets
    [
      # Widget 0 — NE: total de filas en lk_facturacion.
      {
        title: 'NE', type: 'number',
        sql: <<~SQL
          SELECT COUNT(t.id) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 1 — % Gestión = NEs con facturación / NE total * 100.
      {
        title: '% Gestión', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(t.id), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 2 — Presupuesto % = SUM(facturacion) / SUM(presupuesto_c) * 100.
      {
        title: 'Presupuesto', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(t.facturacion)
                   / NULLIF(SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 3 — Participación de Pedidos = NEs con pedido / NE total * 100.
      {
        title: 'Participación de Pedidos', type: 'number',
        sql: <<~SQL
          SELECT ROUND(
                   SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(t.id), 0) * 100, 2
                 ) AS valor
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
        SQL
      },
      # Widget 4 — Venta sin IVA vs Presupuesto por ciclo.
      {
        title: 'Venta sin IVA vs Presupuesto', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 SUM(t.facturacion) AS venta_sin_iva,
                 SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))) AS presupuesto
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 5 — NE con Pedido vs Meta por ciclo.
      {
        title: 'NE con Pedido vs Meta', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido,
                 SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))) AS meta_pedidos
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 6 — NE Total vs NE con Pedido por ciclo.
      {
        title: 'NE Total vs NE con Pedido', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 COUNT(t.id) AS ne_total,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          LEFT JOIN lk_facturacion_leads_c flc ON t.id = flc.lk_facturacion_leadslk_facturacion_idb
          LEFT JOIN leads_cstm lc ON flc.lk_facturacion_leadsleads_ida = lc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 7 — Interacciones por Ciclo (Valiosas: ciclo derivado de DATE_FORMAT(date_start,'%Y%m'),
      # lead vía calls_leads).
      {
        title: 'Interacciones por Ciclo', type: 'bar',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 (SELECT COUNT(DISTINCT cl2.lead_id)
                  FROM calls ca2
                  JOIN calls_leads cl2 ON ca2.id = cl2.call_id
                  WHERE DATE_FORMAT(ca2.date_start, '%Y%m') = t.name
                    AND ca2.deleted = 0) AS ne_gestionados,
                 (SELECT COUNT(ca3.id)
                  FROM calls ca3
                  WHERE DATE_FORMAT(ca3.date_start, '%Y%m') = t.name
                    AND ca3.deleted = 0) AS interacciones
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name ASC
          LIMIT 20
        SQL
      },
      # Widget 8 — Resumen Histórico (tabla). Columnas computadas resueltas en SQL.
      # Nota: en Valiosas, venta_sin_iva usa SUM_NUM (CAST a DECIMAL) según el TS.
      {
        title: 'Resumen Histórico', type: 'table',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 COUNT(t.id) AS ne,
                 SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END) AS ne_con_pedido,
                 ROUND(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                       / NULLIF(COUNT(t.id), 0) * 100, 2) AS pct_efectividad,
                 SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))) AS meta_pedidos,
                 ROUND(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CAST(fc.meta_pedidos_c AS DECIMAL(18,2))), 0) * 100, 2) AS cumplimiento_frecuencia,
                 SUM(CAST(t.facturacion AS DECIMAL(18,2))) AS venta_sin_iva,
                 SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))) AS presupuesto,
                 ROUND(SUM(CAST(t.facturacion AS DECIMAL(18,2)))
                       / NULLIF(SUM(CAST(fc.presupuesto_c AS DECIMAL(18,2))), 0) * 100, 2) AS cumplimiento_presupuesto,
                 ROUND(SUM(CAST(t.facturacion AS DECIMAL(18,2)))
                       / NULLIF(SUM(CASE WHEN t.facturacion > 0 THEN 1 ELSE 0 END), 0), 2) AS orden_promedio,
                 (SELECT COUNT(DISTINCT cl2.lead_id)
                  FROM calls ca2
                  JOIN calls_leads cl2 ON ca2.id = cl2.call_id
                  WHERE DATE_FORMAT(ca2.date_start, '%Y%m') = t.name
                    AND ca2.deleted = 0) AS ne_gestionados,
                 ROUND(
                   (SELECT COUNT(DISTINCT cl2.lead_id)
                    FROM calls ca2
                    JOIN calls_leads cl2 ON ca2.id = cl2.call_id
                    WHERE DATE_FORMAT(ca2.date_start, '%Y%m') = t.name
                      AND ca2.deleted = 0)
                   / NULLIF(COUNT(t.id), 0) * 100, 2) AS pct_ne,
                 (SELECT COUNT(ca3.id)
                  FROM calls ca3
                  WHERE DATE_FORMAT(ca3.date_start, '%Y%m') = t.name
                    AND ca3.deleted = 0) AS interacciones
          FROM lk_facturacion t
          LEFT JOIN lk_facturacion_cstm fc ON t.id = fc.id_c
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name DESC
          LIMIT 50
        SQL
      },
      # Widget 9 — Frecuencia por Ciclo (tabla): NE = leads únicos con llamada en el mes (date_start).
      {
        title: 'Frecuencia por Ciclo', type: 'table',
        sql: <<~SQL
          SELECT t.name AS ciclo,
                 (SELECT COUNT(DISTINCT cl2.lead_id)
                  FROM calls ca2
                  JOIN calls_leads cl2 ON ca2.id = cl2.call_id
                  WHERE DATE_FORMAT(ca2.date_start, '%Y%m') = t.name
                    AND ca2.deleted = 0) AS ne
          FROM lk_facturacion t
          WHERE t.deleted = 0
          GROUP BY t.name
          ORDER BY t.name DESC
          LIMIT 50
        SQL
      }
    ]
  end

  # ────────────────────────────────────────────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────────────────────────────────────────────

  # Carpeta idempotente por nombre (raíz, scope cuenta).
  def find_or_create_folder(name)
    account.jabvox_analytics_folders.find_by(name_jabvox: name, parent_id: nil) ||
      account.jabvox_analytics_folders.create!(
        name_jabvox: name,
        parent_id: nil,
        position_jabvox: 0,
        created_by_id: user&.id
      )
  end

  # data_source_id de la fuente externa por nombre de BD; nil si no existe (no se crean fuentes).
  def data_source_id_for(database_name)
    account.jabvox_analytics_data_sources.find_by(database_jabvox: database_name)&.id
  end
end
