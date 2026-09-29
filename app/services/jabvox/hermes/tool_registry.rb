# frozen_string_literal: true

# Registro declarativo de las tools que Hermes puede ejecutar sobre Jabvox.
#
# Cada tool declara: el permiso requerido, el endpoint interno (método + path relativo a
# /api/v1/accounts/:account_id), y un esquema mínimo de parámetros. Es la ÚNICA fuente de
# verdad de "qué tools existen y qué permiso piden" — el LLM nunca inventa tools ni permisos.
#
# Doble autorización (se valida en HermesAuthorizer, no aquí):
#   NIVEL 1: la cuenta tiene habilitada la tool/MCP.
#   NIVEL 2: el usuario tiene el permiso requerido.
module Jabvox::Hermes::ToolRegistry
  module_function

  # tool_name => { permission:, method:, path:, params:, mcp:, feature: }
  # `path` admite :id como placeholder. `mcp` agrupa la tool bajo un MCP lógico (NIVEL 1).
  # `feature` es el módulo jabvox que la gatea (NIVEL 1.5); 'core' = funcionalidad base sin
  # gate de módulo. TODAS las áreas son de la cuenta y NINGUNA borra (solo read/create/write).
  TOOLS = {
    # --- Etiquetas (labels) — core ---
    'get_labels' => { permission: 'read', method: :get, path: 'labels', mcp: 'jabvox_core', feature: 'core' },
    'create_label' => { permission: 'create', method: :post, path: 'labels',
                        params: { title: :string }, mcp: 'jabvox_core', feature: 'core' },
    'update_label' => { permission: 'write', method: :patch, path: 'labels/:id',
                        params: { id: :integer, title: :string, show_on_sidebar: :boolean },
                        mcp: 'jabvox_core', feature: 'core' },

    # --- Bandejas (inboxes) — core, solo lectura (crear inbox es sensible/infra) ---
    'get_inboxes' => { permission: 'read', method: :get, path: 'inboxes', mcp: 'jabvox_core', feature: 'core' },

    # --- Contactos — core ---
    'search_contacts' => { permission: 'read', method: :get, path: 'contacts/search',
                           params: { q: :string }, mcp: 'jabvox_core', feature: 'core' },
    'get_contact' => { permission: 'read', method: :get, path: 'contacts/:id',
                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_contact' => { permission: 'create', method: :post, path: 'contacts',
                          params: { name: :string, email: :string, phone_number: :string },
                          mcp: 'jabvox_core', feature: 'core' },
    'update_contact' => { permission: 'write', method: :patch, path: 'contacts/:id',
                          params: { id: :integer, name: :string, email: :string, phone_number: :string },
                          mcp: 'jabvox_core', feature: 'core' },

    # --- Conversaciones + mensajes — core ---
    'get_conversations_meta' => { permission: 'read', method: :get, path: 'conversations/meta',
                                  params: { since: :string, until: :string, inbox_id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    # Lista conversaciones con filtros (estado, inbox, contacto) y paginación por cursor.
    'list_conversations' => { permission: 'read', method: :get, path: 'conversations',
                              params: { status: :string, inbox_id: :integer, contact_id: :integer,
                                        since: :string, until: :string,
                                        before_id: :integer, limit: :integer },
                              mcp: 'jabvox_core', feature: 'core' },
    'get_conversation_messages' => { permission: 'read', method: :get, path: 'conversations/:id/messages',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    # Resumen estructurado de una conversación (metadatos + últimos mensajes) para que
    # Hermes lo resuma; no llama al LLM, solo entrega el material listo.
    'summarize_conversation' => { permission: 'read', method: :get, path: 'conversations/:id/summary',
                                  params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'reply_conversation' => { permission: 'write', method: :post, path: 'conversations/:id/messages',
                              params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },
    # Nota privada de una conversación (mensaje interno, no visible al cliente).
    'add_private_note' => { permission: 'create', method: :post, path: 'conversations/:id/notes',
                            params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },

    # --- Notas de contacto — core ---
    'get_contact_notes' => { permission: 'read', method: :get, path: 'contacts/:id/notes',
                             params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_contact_note' => { permission: 'create', method: :post, path: 'contacts/:id/notes',
                               params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'core' },

    # --- Automatizaciones — core (flujos de automatización) ---
    'get_automation_rules' => { permission: 'read', method: :get, path: 'automation_rules',
                                mcp: 'jabvox_core', feature: 'core' },
    'create_automation_rule' => { permission: 'create', method: :post, path: 'automation_rules',
                                  params: { name: :string, event_name: :string,
                                            conditions: :json, actions: :json },
                                  mcp: 'jabvox_core', feature: 'core' },
    'update_automation_rule' => { permission: 'write', method: :patch, path: 'automation_rules/:id',
                                  params: { id: :integer, name: :string, active: :boolean,
                                            conditions: :json, actions: :json },
                                  mcp: 'jabvox_core', feature: 'core' },

    # --- Integración por WEBHOOK directo al Hermes de la cuenta (así responde bandejas) ---
    # Hermes NO es un AgentBot de Jabvox: se integra como un webhook. Jabvox dispara el evento
    # message_created hacia el Hermes de ESTA cuenta (URL fijada por Jabvox, no por el LLM);
    # el Hermes recibe el mensaje, razona y responde llamando de vuelta a reply_conversation.
    'get_webhooks' => { permission: 'read', method: :get, path: 'webhooks',
                        mcp: 'jabvox_core', feature: 'core' },
    # Crea la integración de webhook Hermes para TODAS las bandejas (account_type).
    'create_hermes_webhook' => { permission: 'create', method: :post, path: 'webhooks',
                                 params: {}, mcp: 'jabvox_core', feature: 'core' },
    # Crea la integración de webhook Hermes para UNA bandeja concreta (inbox_type).
    'create_hermes_inbox_webhook' => { permission: 'create', method: :post, path: 'webhooks/inbox',
                                       params: { inbox_id: :integer }, mcp: 'jabvox_core', feature: 'core' },

    # --- Gestiones (management states) ---
    'get_management_states' => { permission: 'read', method: :get, path: 'jabvox/management_states',
                                 mcp: 'jabvox_management', feature: 'core' },
    'create_management_state' => { permission: 'create', method: :post, path: 'jabvox/management_states',
                                   params: { name: :string }, mcp: 'jabvox_management', feature: 'core' },
    'update_management_state' => { permission: 'write', method: :patch, path: 'jabvox/management_states/:id',
                                   params: { id: :integer, name: :string }, mcp: 'jabvox_management', feature: 'core' },

    # --- Campañas del dialer (gateado por jabvox_dialer) ---
    'get_dialer_campaigns' => { permission: 'read', method: :get, path: 'jabvox/dialer_campaigns',
                                mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'get_dialer_campaign' => { permission: 'read', method: :get, path: 'jabvox/dialer_campaigns/:id',
                               params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'create_dialer_campaign' => { permission: 'create', method: :post, path: 'jabvox/dialer_campaigns',
                                  params: { name: :string }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'update_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id',
                                  params: { id: :integer, name: :string }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },

    # --- Envíos masivos: SMS (jabvox_sms) ---
    'get_sms_campaigns' => { permission: 'read', method: :get, path: 'jabvox/sms_campaigns',
                             params: { since: :string, until: :string, limit: :integer },
                             mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'create_sms_campaign' => { permission: 'create', method: :post, path: 'jabvox/sms_campaigns',
                               params: { name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'update_sms_campaign' => { permission: 'write', method: :patch, path: 'jabvox/sms_campaigns/:id',
                               params: { id: :integer, name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },

    # --- Reportes de la cuenta (solo lectura) ---
    'get_report_summary' => { permission: 'read', method: :get, path: 'jabvox/reports/agents',
                              params: { since: :string, until: :string },
                              mcp: 'analytics', feature: 'core' },
    'get_agents_report' => { permission: 'read', method: :get, path: 'jabvox/reports/agents',
                             params: { since: :string, until: :string }, mcp: 'analytics', feature: 'core' },
    'get_products_report' => { permission: 'read', method: :get, path: 'jabvox/reports/products',
                               params: { since: :string, until: :string }, mcp: 'jabvox_core',
                               feature: 'jabvox_products' },
    'get_dialer_report' => { permission: 'read', method: :get, path: 'jabvox/reports/dialer',
                             params: { since: :string, until: :string }, mcp: 'jabvox_core',
                             feature: 'jabvox_dialer' },
    'get_agent_status_report' => { permission: 'read', method: :get, path: 'jabvox/reports/agent_status',
                                   mcp: 'analytics', feature: 'core' },
    'get_hermes_activity_report' => { permission: 'read', method: :get, path: 'jabvox/reports/hermes_activity',
                                      params: { since: :string, until: :string }, mcp: 'jabvox_core',
                                      feature: 'jabvox_ai_chat' },

    # --- Análisis de Audio (módulo jabvox_audio_analysis) ---
    'get_audio_jobs' => { permission: 'read', method: :get, path: 'jabvox/audio/jobs',
                          params: { status: :string, since: :string, until: :string, limit: :integer },
                          mcp: 'jabvox_core', feature: 'jabvox_audio_analysis' },
    'get_audio_job' => { permission: 'read', method: :get, path: 'jabvox/audio/jobs/:id',
                         params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_audio_analysis' },
    'get_audio_pipelines' => { permission: 'read', method: :get, path: 'jabvox/audio/pipelines',
                               mcp: 'jabvox_core', feature: 'jabvox_audio_analysis' },

    # --- Analytics / Bases de datos externas (módulo jabvox_analytics) ---
    'get_analytics_data_sources' => { permission: 'read', method: :get, path: 'jabvox/analytics/data_sources',
                                      mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_data_source' => { permission: 'read', method: :get, path: 'jabvox/analytics/data_sources/:id',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_data_source_schema' => { permission: 'read', method: :get,
                                            path: 'jabvox/analytics/data_sources/:id/schema',
                                            params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Ejecuta SQL read-only sobre una BD externa. Hermes NO pasa credenciales:
    # van guardadas y cifradas en la data_source; el backend las usa. Validado
    # read-only (rechaza INSERT/UPDATE/DELETE/DROP y multi-sentencia).
    'run_analytics_query' => { permission: 'read', method: :post, path: 'jabvox/analytics/data_sources/:id/custom_sql',
                               params: { id: :integer, sql: :string }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'preview_analytics_table' => { permission: 'read', method: :get,
                                   path: 'jabvox/analytics/data_sources/:id/preview',
                                   params: { id: :integer, table: :string, page: :integer, per_page: :integer },
                                   mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_dashboards' => { permission: 'read', method: :get, path: 'jabvox/analytics/dashboards',
                                    mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_dashboard' => { permission: 'read', method: :get, path: 'jabvox/analytics/dashboards/:id',
                                   params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Crea un dashboard vacío. Los widgets se añaden con create_analytics_widget.
    # Solo usa data sources YA conectadas por un admin; Hermes nunca maneja credenciales.
    'create_analytics_dashboard' => { permission: 'create', method: :post, path: 'jabvox/analytics/dashboards',
                                      params: { name: :string, description: :string, folder_id: :integer },
                                      mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'update_analytics_dashboard' => { permission: 'write', method: :patch, path: 'jabvox/analytics/dashboards/:id',
                                      params: { id: :integer, name: :string, description: :string,
                                                folder_id: :integer },
                                      mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Guarda un query como widget dentro de un dashboard. Con custom_sql (SQL
    # read-only contra la BD externa de la data_source) o un query visual.
    # widget_type: table|number|indicator|bar|line|area|pie|donut|... (ver lista).
    'create_analytics_widget' => { permission: 'create', method: :post,
                                   path: 'jabvox/analytics/dashboards/:dashboard_id/widgets',
                                   params: { dashboard_id: :integer, title: :string, widget_type: :string,
                                             data_source_id: :integer, custom_sql: :string, query_spec: :json,
                                             config: :json },
                                   mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'update_analytics_widget' => { permission: 'write', method: :patch,
                                   path: 'jabvox/analytics/dashboards/:dashboard_id/widgets/:id',
                                   params: { dashboard_id: :integer, id: :integer, title: :string,
                                             widget_type: :string, data_source_id: :integer,
                                             custom_sql: :string, query_spec: :json, config: :json },
                                   mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Ejecuta un widget guardado y devuelve sus filas (read-only).
    'execute_analytics_widget' => { permission: 'read', method: :post,
                                    path: 'jabvox/analytics/dashboards/:dashboard_id/widgets/:id/execute',
                                    params: { dashboard_id: :integer, id: :integer },
                                    mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Carpetas para organizar dashboards.
    'get_analytics_folders' => { permission: 'read', method: :get, path: 'jabvox/analytics/folders',
                                 mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'create_analytics_folder' => { permission: 'create', method: :post, path: 'jabvox/analytics/folders',
                                   params: { name: :string }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'update_analytics_folder' => { permission: 'write', method: :patch, path: 'jabvox/analytics/folders/:id',
                                   params: { id: :integer, name: :string },
                                   mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Reportes cruzados: unen datos de VARIAS fuentes externas por un campo común.
    'get_analytics_cross_reports' => { permission: 'read', method: :get, path: 'jabvox/analytics/cross_reports',
                                       mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_cross_report' => { permission: 'read', method: :get, path: 'jabvox/analytics/cross_reports/:id',
                                      params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'execute_analytics_cross_report' => { permission: 'read', method: :post,
                                          path: 'jabvox/analytics/cross_reports/:id/execute',
                                          params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    # Resumen general del módulo + reportes internos pre-armados (scoped a la cuenta).
    'get_analytics_overview_stats' => { permission: 'read', method: :get,
                                        path: 'jabvox/analytics/dashboards/overview_stats',
                                        mcp: 'jabvox_core', feature: 'jabvox_analytics' },
    'get_analytics_internal_reports' => { permission: 'read', method: :get,
                                          path: 'jabvox/analytics/dashboards/internal_reports',
                                          mcp: 'jabvox_core', feature: 'jabvox_analytics' },

    # --- Importar Leads (módulo jabvox_lead_import): pull desde BD externa ---
    'get_lead_import_sources' => { permission: 'read', method: :get, path: 'jabvox/lead_import/sources',
                                   mcp: 'jabvox_core', feature: 'jabvox_lead_import' },
    'get_lead_import_source' => { permission: 'read', method: :get, path: 'jabvox/lead_import/sources/:id',
                                  params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_lead_import' },
    'trigger_lead_import_sync' => { permission: 'write', method: :post, path: 'jabvox/lead_import/sources/:id/sync',
                                    params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_lead_import' },
    'get_lead_import_sync_status' => { permission: 'read', method: :get,
                                       path: 'jabvox/lead_import/sources/:id/sync_status',
                                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_lead_import' },

    # --- Exportar Datos (módulo jabvox_data_export) ---
    'get_data_export_targets' => { permission: 'read', method: :get, path: 'jabvox/data_export/targets',
                                   mcp: 'jabvox_core', feature: 'jabvox_data_export' },
    'get_data_export_target' => { permission: 'read', method: :get, path: 'jabvox/data_export/targets/:id',
                                  params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_data_export' },
    'trigger_data_export_sync' => { permission: 'write', method: :post,
                                    path: 'jabvox/data_export/targets/:id/sync_now',
                                    params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_data_export' },

    # --- Pedidos y comercial (módulo jabvox_products) ---
    'get_orders' => { permission: 'read', method: :get, path: 'jabvox/orders',
                      params: { status: :string, doc_type: :string }, mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_order' => { permission: 'read', method: :get, path: 'jabvox/orders/:id',
                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_products' => { permission: 'read', method: :get, path: 'jabvox/products',
                        params: { limit: :integer },
                        mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_product' => { permission: 'read', method: :get, path: 'jabvox/products/:id',
                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_products' },

    # --- Tareas (módulo jabvox_tasks) ---
    'get_tasks' => { permission: 'read', method: :get, path: 'jabvox/tasks',
                     params: { board_id: :integer, stage_id: :integer, assignee_id: :integer, since: :string, until: :string, limit: :integer },
                     mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'get_task_boards' => { permission: 'read', method: :get, path: 'jabvox/tasks/boards',
                           params: { id: :integer, limit: :integer },
                           mcp: 'jabvox_core', feature: 'jabvox_tasks' },

    # --- Calendario (módulo jabvox_calendar) ---
    'get_calendar_events' => { permission: 'read', method: :get, path: 'jabvox/calendar/events',
                               params: { since: :string, until: :string, limit: :integer, branch_id: :integer },
                               mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    # Sedes: dónde se atiende, con su zona horaria y su horario comercial. Hermes las lee
    # para saber en qué sede agendar; crearlas sigue siendo cosa del administrador.
    'get_calendar_branches' => { permission: 'read', method: :get, path: 'jabvox/calendar/branches',
                                 params: {},
                                 mcp: 'jabvox_core', feature: 'jabvox_calendar' },

    # --- Tickets (módulo jabvox_tickets) ---
    'get_tickets' => { permission: 'read', method: :get, path: 'jabvox/tickets',
                       params: { status_jabvox: :string, priority_jabvox: :string, since: :string, until: :string, limit: :integer },
                       mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'get_ticket' => { permission: 'read', method: :get, path: 'jabvox/tickets/:id',
                      params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },

    # --- Kanban (módulo jabvox_kanban) ---
    'get_kanban_funnels' => { permission: 'read', method: :get, path: 'jabvox/kanban_funnels',
                              params: { id: :integer, limit: :integer },
                              mcp: 'jabvox_core', feature: 'jabvox_kanban' },

    # --- Flows / automatizaciones avanzadas (módulo jabvox_advanced_automations) ---
    'get_flows' => { permission: 'read', method: :get, path: 'jabvox/flows',
                     mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'run_flow' => { permission: 'write', method: :post, path: 'jabvox/flows/:id/run',
                    params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },

    # --- Automatizaciones BÁSICAS (reglas): activar/desactivar y clonar (core) ---
    'get_automation_rule' => { permission: 'read', method: :get, path: 'automation_rules/:id',
                               params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'toggle_automation_rule' => { permission: 'write', method: :patch, path: 'automation_rules/:id/toggle',
                                  params: { id: :integer, active: :boolean }, mcp: 'jabvox_core', feature: 'core' },
    'clone_automation_rule' => { permission: 'create', method: :post, path: 'automation_rules/:id/clone',
                                 params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },

    # --- Automatizaciones AVANZADAS (flows): ciclo de vida (jabvox_advanced_automations) ---
    'get_flow' => { permission: 'read', method: :get, path: 'jabvox/flows/:id',
                    params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'create_flow' => { permission: 'create', method: :post, path: 'jabvox/flows',
                       params: { name: :string, description: :string, folder_id: :integer },
                       mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'update_flow' => { permission: 'write', method: :patch, path: 'jabvox/flows/:id',
                       params: { id: :integer, name: :string, description: :string, folder_id: :integer },
                       mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'set_flow_status' => { permission: 'write', method: :patch, path: 'jabvox/flows/:id/status',
                           params: { id: :integer, status: :string },
                           mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'duplicate_flow' => { permission: 'create', method: :post, path: 'jabvox/flows/:id/duplicate',
                          params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    'validate_flow' => { permission: 'read', method: :get, path: 'jabvox/flows/:id/validate',
                         params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    # Catálogo de tipos de nodo disponibles (para saber qué nodos se pueden crear).
    'get_flow_node_types' => { permission: 'read', method: :get, path: 'jabvox/flows/node_types',
                               mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    # Guarda el grafo (nodos + conexiones) de un flujo como versión nueva. Valida antes.
    'save_flow_graph' => { permission: 'write', method: :post, path: 'jabvox/flows/:id/save_version',
                           params: { id: :integer, nodes: :json, edges: :json, notes: :json, strict: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },
    # Prueba UN nodo del flujo aisladamente (ejecución de prueba, sin activar el flujo).
    'test_flow_node' => { permission: 'write', method: :post, path: 'jabvox/flows/:id/run_node',
                          params: { id: :integer, node_id: :string, prior_outputs: :json },
                          mcp: 'jabvox_core', feature: 'jabvox_advanced_automations' },

    # --- Envíos masivos WhatsApp (módulo jabvox_bulk_whatsapp) ---
    'get_bulk_whatsapp_batches' => { permission: 'read', method: :get, path: 'jabvox/bulk_whatsapp/batches',
                                     params: { since: :string, until: :string, limit: :integer },
                                     mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },

    # --- Plantillas WhatsApp (módulo jabvox_whatsapp_templates) ---
    'get_whatsapp_templates' => { permission: 'read', method: :get, path: 'jabvox/whatsapp_templates/templates',
                                  mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    'create_whatsapp_template' => { permission: 'create', method: :post, path: 'jabvox/whatsapp_templates/templates',
                                    params: { name: :string, category: :string, language: :string, inbox_id: :integer,
                                              header_type: :string, header_content: :string, body: :string,
                                              footer: :string, buttons: :json },
                                    mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    'update_whatsapp_template' => { permission: 'write', method: :patch, path: 'jabvox/whatsapp_templates/templates/:id',
                                    params: { id: :integer, name: :string, category: :string, language: :string,
                                              header_type: :string, header_content: :string, body: :string,
                                              footer: :string, buttons: :json },
                                    mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    'duplicate_whatsapp_template' => { permission: 'create', method: :post, path: 'jabvox/whatsapp_templates/templates/:id/duplicate',
                                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    'sync_whatsapp_template' => { permission: 'write', method: :post, path: 'jabvox/whatsapp_templates/templates/:id/sync',
                                  params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    'send_whatsapp_template_to_contact' => { permission: 'write', method: :post, path: 'jabvox/whatsapp_templates/templates/:id/send_to_contact',
                                             params: { template_id: :integer, contact_id: :integer },
                                             mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },
    # Envío masivo de WhatsApp: reutilizar un lote previo (reenvío controlado).
    'reuse_bulk_whatsapp_batch' => { permission: 'create', method: :post, path: 'jabvox/bulk_whatsapp/batches/:id/reuse',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },
    'get_bulk_whatsapp_batch' => { permission: 'read', method: :get, path: 'jabvox/bulk_whatsapp/batches/:id',
                                   params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },
    # Crea y lanza un envío masivo a leads (acción disruptiva: envía mensajes reales).
    # inbox_id + sender_user_id + template_name/language o text libre. leads: all + filters
    # o lead_ids explícitos. variable_map mapea {{n}} -> campo del lead.
    'create_bulk_whatsapp_batch' => { permission: 'create', method: :post, path: 'jabvox/bulk_whatsapp/batches',
                                      params: { inbox_id: :integer, sender_user_id: :integer, source: :string,
                                                template_name: :string, language: :string, text: :string,
                                                all: :boolean, lead_ids: :json, excluded_ids: :json,
                                                filters: :json, variable_map: :json, response_email: :string },
                                      mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },

    # --- Grupos de WhatsApp (módulo jabvox_whatsapp_groups) ---
    'get_whatsapp_groups' => { permission: 'read', method: :get, path: 'jabvox/whatsapp_groups/groups',
                               mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },
    'get_whatsapp_group' => { permission: 'read', method: :get, path: 'jabvox/whatsapp_groups/groups/:id',
                              params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },
    'create_whatsapp_group' => { permission: 'create', method: :post, path: 'jabvox/whatsapp_groups/groups',
                                 params: { inbox_id: :integer, name: :string, description: :string,
                                           member_phones: :json },
                                 mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },
    'update_whatsapp_group' => { permission: 'write', method: :patch, path: 'jabvox/whatsapp_groups/groups/:id',
                                 params: { id: :integer, name: :string, description: :string },
                                 mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },
    'add_whatsapp_group_member' => { permission: 'write', method: :post,
                                     path: 'jabvox/whatsapp_groups/groups/:id/members',
                                     params: { id: :integer, phone: :string },
                                     mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },
    'send_whatsapp_group_message' => { permission: 'write', method: :post,
                                       path: 'jabvox/whatsapp_groups/groups/:id/messages',
                                       params: { id: :integer, text: :string },
                                       mcp: 'jabvox_core', feature: 'jabvox_whatsapp_groups' },

    # --- Voice Broadcast (módulo jabvox_voice_broadcast): campañas de audio pregrabado.
    # Hermes GESTIONA campañas (crear/editar/iniciar/pausar); el backend hace la marcación
    # real. NUNCA toca AMI/VoIP ni origina llamadas a mano.
    'get_voice_broadcasts' => { permission: 'read', method: :get, path: 'jabvox/voice_broadcasts',
                                params: { since: :string, until: :string, limit: :integer },
                                mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'get_voice_broadcast' => { permission: 'read', method: :get, path: 'jabvox/voice_broadcasts/:id',
                               params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'get_voice_broadcast_report' => { permission: 'read', method: :get, path: 'jabvox/voice_broadcasts/:id/report',
                                      params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'create_voice_broadcast' => { permission: 'create', method: :post, path: 'jabvox/voice_broadcasts',
                                  params: { name_jabvox: :string, caller_id_jabvox: :string,
                                            max_concurrent_jabvox: :integer, cps_jabvox: :integer,
                                            max_retries_jabvox: :integer, retry_interval_jabvox: :integer,
                                            calling_hours_start_jabvox: :string, calling_hours_end_jabvox: :string,
                                            countries_jabvox: :json, management_state_ids_jabvox: :json,
                                            affiliate_ids_jabvox: :json, inbox_ids_jabvox: :json },
                                  mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'update_voice_broadcast' => { permission: 'write', method: :patch, path: 'jabvox/voice_broadcasts/:id',
                                  params: { id: :integer, name_jabvox: :string, caller_id_jabvox: :string,
                                            max_concurrent_jabvox: :integer, cps_jabvox: :integer,
                                            max_retries_jabvox: :integer, retry_interval_jabvox: :integer,
                                            calling_hours_start_jabvox: :string, calling_hours_end_jabvox: :string },
                                  mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'start_voice_broadcast' => { permission: 'write', method: :post, path: 'jabvox/voice_broadcasts/:id/start',
                                 params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'pause_voice_broadcast' => { permission: 'write', method: :post, path: 'jabvox/voice_broadcasts/:id/pause',
                                 params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'resume_voice_broadcast' => { permission: 'write', method: :post, path: 'jabvox/voice_broadcasts/:id/resume',
                                  params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },
    'stop_voice_broadcast' => { permission: 'write', method: :post, path: 'jabvox/voice_broadcasts/:id/stop',
                                params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_voice_broadcast' },

    # --- Afiliados (módulo jabvox_affiliates) ---
    'get_affiliates' => { permission: 'read', method: :get, path: 'jabvox/affiliates',
                          params: { id: :integer, limit: :integer },
                          mcp: 'jabvox_core', feature: 'jabvox_affiliates' },

    # --- Campañas (catálogo de la cuenta) ---
    'get_campaigns' => { permission: 'read', method: :get, path: 'jabvox/campaigns',
                         mcp: 'jabvox_core', feature: 'core' },

    # --- CDR (módulo jabvox_cdr) ---
    'get_cdr_records' => { permission: 'read', method: :get, path: 'jabvox/cdr/records',
                           params: { since: :string, until: :string, disposition: :string, src: :string, dst: :string, limit: :integer },
                           mcp: 'jabvox_core', feature: 'jabvox_cdr' },

    # --- Tablas personalizadas (gateadas por el módulo jabvox_customization) ---
    'get_custom_tables' => { permission: 'read', method: :get, path: 'jabvox/custom_tables',
                             mcp: 'jabvox_core', feature: 'jabvox_customization' },

    # ========================================================================
    # LOTE "TODO ES TODO": escritura por módulo (create/write; nunca delete).
    # ========================================================================

    # --- Comunicación: bandeja API + conversaciones (core) ---
    'create_api_inbox' => { permission: 'create', method: :post, path: 'inboxes',
                            params: { name: :string, webhook_url: :string },
                            mcp: 'jabvox_core', feature: 'core' },
    'update_conversation_status' => { permission: 'write', method: :post, path: 'conversations/:id/toggle_status',
                                      params: { id: :integer, status: :string, snoozed_until: :string },
                                      mcp: 'jabvox_core', feature: 'core' },
    'assign_conversation' => { permission: 'write', method: :post, path: 'conversations/:id/assignments',
                               params: { id: :integer, assignee_id: :integer, team_id: :integer },
                               mcp: 'jabvox_core', feature: 'core' },

    # --- Plantillas de correo (jabvox_email) ---
    'get_email_templates' => { permission: 'read', method: :get, path: 'jabvox/email_templates',
                               params: { since: :string, until: :string, limit: :integer },
                               mcp: 'jabvox_core', feature: 'jabvox_email' },
    'create_email_template' => { permission: 'create', method: :post, path: 'jabvox/email_templates',
                                 params: { name: :string, subject: :string, body: :string, active: :boolean },
                                 mcp: 'jabvox_core', feature: 'jabvox_email' },
    'update_email_template' => { permission: 'write', method: :patch, path: 'jabvox/email_templates/:id',
                                 params: { id: :integer, name: :string, subject: :string, body: :string, active: :boolean },
                                 mcp: 'jabvox_core', feature: 'jabvox_email' },
    'test_send_email_template' => { permission: 'write', method: :post, path: 'jabvox/email_templates/:id/test_send',
                                    params: { id: :integer, to: :string }, mcp: 'jabvox_core', feature: 'jabvox_email' },
    'send_email_template_to_contact' => { permission: 'write', method: :post, path: 'jabvox/email_templates/:id/send_to_contact',
                                          params: { id: :integer, contact_id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_email' },

    # --- Formularios (jabvox_forms) ---
    'get_forms' => { permission: 'read', method: :get, path: 'jabvox/forms', mcp: 'jabvox_core', feature: 'jabvox_forms' },
    'get_form' => { permission: 'read', method: :get, path: 'jabvox/forms/:id', params: { id: :integer },
                    mcp: 'jabvox_core', feature: 'jabvox_forms' },
    'create_form' => { permission: 'create', method: :post, path: 'jabvox/forms',
                       params: { name_jabvox: :string, slug_jabvox: :string, submit_button_text_jabvox: :string,
                                 active_jabvox: :boolean, fields_jabvox: :json },
                       mcp: 'jabvox_core', feature: 'jabvox_forms' },
    'update_form' => { permission: 'write', method: :patch, path: 'jabvox/forms/:id',
                       params: { id: :integer, name_jabvox: :string, slug_jabvox: :string,
                                 submit_button_text_jabvox: :string, active_jabvox: :boolean, fields_jabvox: :json },
                       mcp: 'jabvox_core', feature: 'jabvox_forms' },

    # --- Tareas (jabvox_tasks) ---
    'create_task' => { permission: 'create', method: :post, path: 'jabvox/tasks',
                       params: { title_jabvox: :string, board_id: :integer, stage_id: :integer, contact_id: :integer,
                                 assignee_id: :integer, description_jabvox: :string, priority_jabvox: :string,
                                 status_jabvox: :string, due_at_jabvox: :string },
                       mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'update_task' => { permission: 'write', method: :patch, path: 'jabvox/tasks/:id',
                       params: { id: :integer, title_jabvox: :string, stage_id: :integer, assignee_id: :integer,
                                 description_jabvox: :string, priority_jabvox: :string, status_jabvox: :string, due_at_jabvox: :string },
                       mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'move_task' => { permission: 'write', method: :patch, path: 'jabvox/tasks/:id/move',
                     params: { id: :integer, stage_id: :integer, position: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'create_task_board' => { permission: 'create', method: :post, path: 'jabvox/task_boards',
                             params: { name_jabvox: :string, description_jabvox: :string, position_jabvox: :integer, is_active_jabvox: :boolean },
                             mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'update_task_board' => { permission: 'write', method: :patch, path: 'jabvox/task_boards/:id',
                             params: { id: :integer, name_jabvox: :string, description_jabvox: :string, position_jabvox: :integer, is_active_jabvox: :boolean },
                             mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'create_task_stage' => { permission: 'create', method: :post, path: 'jabvox/task_stages',
                             params: { board_id: :integer, name_jabvox: :string, color_jabvox: :string, position_jabvox: :integer },
                             mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'update_task_stage' => { permission: 'write', method: :patch, path: 'jabvox/task_stages/:id',
                             params: { id: :integer, name_jabvox: :string, color_jabvox: :string, position_jabvox: :integer },
                             mcp: 'jabvox_core', feature: 'jabvox_tasks' },

    # --- Calendario (jabvox_calendar) ---
    'create_calendar_event' => { permission: 'create', method: :post, path: 'jabvox/calendar/events',
                                 params: { title: :string, start_at: :string, end_at: :string, all_day: :boolean,
                                           description: :string, note: :string, event_type: :string, status: :string,
                                           color: :string, contact_id: :integer, branch_id: :integer },
                                 mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'update_calendar_event' => { permission: 'write', method: :patch, path: 'jabvox/calendar/events/:id',
                                 params: { id: :integer, title: :string, description: :string, note: :string,
                                           event_type: :string, status: :string, color: :string,
                                           contact_id: :integer, branch_id: :integer },
                                 mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'create_calendar_external_person' => { permission: 'create', method: :post, path: 'jabvox/calendar/external_people',
                                           params: { name: :string, email: :string, phone_number: :string, notes: :string, color: :string },
                                           mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'update_calendar_external_person' => { permission: 'write', method: :patch, path: 'jabvox/calendar/external_people/:id',
                                           params: { id: :integer, name: :string, email: :string, phone_number: :string, notes: :string, color: :string },
                                           mcp: 'jabvox_core', feature: 'jabvox_calendar' },

    # --- Chat interno de equipo (jabvox_internal_chat) ---
    'get_internal_chats' => { permission: 'read', method: :get, path: 'jabvox/internal_chats',
                              params: { since: :string, until: :string, limit: :integer },
                              mcp: 'jabvox_core', feature: 'jabvox_internal_chat' },
    'create_internal_chat' => { permission: 'create', method: :post, path: 'jabvox/internal_chats',
                                params: { chat_type: :string, name: :string, member_ids: :json, user_id: :integer },
                                mcp: 'jabvox_core', feature: 'jabvox_internal_chat' },
    'send_internal_chat_message' => { permission: 'write', method: :post, path: 'jabvox/internal_chats/:id/send_message',
                                      params: { id: :integer, content: :string }, mcp: 'jabvox_core', feature: 'jabvox_internal_chat' },
    'mark_internal_chat_read' => { permission: 'write', method: :post, path: 'jabvox/internal_chats/:id/mark_read',
                                   params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_internal_chat' },

    # --- Kanban (jabvox_kanban) ---
    'create_kanban_funnel' => { permission: 'create', method: :post, path: 'jabvox/kanban_funnels',
                                params: { name_jabvox: :string, description_jabvox: :string, position_jabvox: :integer,
                                          active_jabvox: :boolean, include_own_contacts_jabvox: :boolean },
                                mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'update_kanban_funnel' => { permission: 'write', method: :patch, path: 'jabvox/kanban_funnels/:id',
                                params: { id: :integer, name_jabvox: :string, description_jabvox: :string, position_jabvox: :integer,
                                          active_jabvox: :boolean, include_own_contacts_jabvox: :boolean },
                                mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'create_kanban_stage' => { permission: 'create', method: :post, path: 'jabvox/kanban_stages',
                               params: { kanban_funnel_id: :integer, name_jabvox: :string, description_jabvox: :string,
                                         color_jabvox: :string, position_jabvox: :integer },
                               mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'update_kanban_stage' => { permission: 'write', method: :patch, path: 'jabvox/kanban_stages/:id',
                               params: { id: :integer, name_jabvox: :string, description_jabvox: :string,
                                         color_jabvox: :string, position_jabvox: :integer },
                               mcp: 'jabvox_core', feature: 'jabvox_kanban' },

    # --- Gestiones (core; gate por permiso) ---
    'export_management_states' => { permission: 'read', method: :get, path: 'jabvox/management_states/export',
                                    mcp: 'jabvox_management', feature: 'core' },

    # --- Dialer / marcador (jabvox_dialer) ---
    'start_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/start',
                                 params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'pause_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/pause',
                                 params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'stop_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/stop',
                                params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'retry_dialer_campaign' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/retry_contacts',
                                 params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'redial_dialer_lead' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/redial_lead',
                              params: { id: :integer, contact_id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'exclude_dialer_lead' => { permission: 'write', method: :patch, path: 'jabvox/dialer_campaigns/:id/exclude_lead',
                               params: { id: :integer, contact_id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'import_dialer_contacts' => { permission: 'create', method: :post, path: 'jabvox/dialer_campaigns/:id/import_contacts',
                                  params: { id: :integer, contacts: :json }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'get_dialer_campaign_progress' => { permission: 'read', method: :get, path: 'jabvox/dialer_campaigns/:id/progress',
                                        params: { id: :integer }, mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'get_dialer_states' => { permission: 'read', method: :get, path: 'jabvox/dialer_states', mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'create_dialer_state' => { permission: 'create', method: :post, path: 'jabvox/dialer_states',
                               params: { name: :string, color: :string, position: :integer, is_active: :boolean },
                               mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'update_dialer_state' => { permission: 'write', method: :patch, path: 'jabvox/dialer_states/:id',
                               params: { id: :integer, name: :string, color: :string, position: :integer, is_active: :boolean },
                               mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'get_dialer_call_logs' => { permission: 'read', method: :get, path: 'jabvox/dialer_call_logs', mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },
    'typify_dialer_call' => { permission: 'write', method: :patch, path: 'jabvox/dialer_call_logs/typify',
                              params: { id: :integer, contact_id: :integer, typification_id: :integer, notes_jabvox: :string, uniqueid: :string },
                              mcp: 'jabvox_dialer', feature: 'jabvox_dialer' },

    # --- Click-to-call (jabvox_click_to_call) ---
    'get_click_to_call_logs' => { permission: 'read', method: :get, path: 'jabvox/click_to_call/call_logs',
                                  params: { since: :string, until: :string, limit: :integer },
                                  mcp: 'jabvox_core', feature: 'jabvox_click_to_call' },
    'typify_click_to_call' => { permission: 'write', method: :patch, path: 'jabvox/click_to_call/call_logs/:id',
                                params: { id: :integer, typification_id: :integer, note: :string },
                                mcp: 'jabvox_core', feature: 'jabvox_click_to_call' },

    # --- CDR (jabvox_cdr) ---
    'sync_cdr_now' => { permission: 'write', method: :post, path: 'jabvox/cdr/sync_now', mcp: 'jabvox_core', feature: 'jabvox_cdr' },
    'analyze_cdr_call' => { permission: 'write', method: :post, path: 'jabvox/cdr/analyze',
                            params: { uniqueid: :string, pipeline_id: :integer, force: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_cdr' },
    'typify_cdr_call' => { permission: 'write', method: :post, path: 'jabvox/cdr/typify',
                           params: { uniqueid: :string, typification_id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_cdr' },

    # --- Tickets (jabvox_tickets) ---
    'create_ticket' => { permission: 'create', method: :post, path: 'jabvox/tickets/tickets',
                         params: { title_jabvox: :string, description_jabvox: :string, ticket_category_id: :integer,
                                   priority_jabvox: :string, conversation_id: :integer },
                         mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'update_ticket' => { permission: 'write', method: :patch, path: 'jabvox/tickets/tickets/:id',
                         params: { id: :integer, title_jabvox: :string, description_jabvox: :string,
                                   ticket_category_id: :integer, priority_jabvox: :string },
                         mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'assign_ticket' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/assign',
                         params: { id: :integer, assignee_id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'change_ticket_status' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/change_status',
                                params: { id: :integer, status: :string }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'resolve_ticket' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/resolve',
                          params: { id: :integer, resolution: :string, resolution_type: :string }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'reopen_ticket' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/reopen',
                         params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'rate_ticket' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/rate',
                       params: { id: :integer, rating: :integer, comment: :string }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'merge_ticket' => { permission: 'write', method: :post, path: 'jabvox/tickets/tickets/:id/merge',
                        params: { id: :integer, target_id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'get_ticket_comments' => { permission: 'read', method: :get, path: 'jabvox/tickets/tickets/:id/comments',
                               params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'create_ticket_comment' => { permission: 'create', method: :post, path: 'jabvox/tickets/tickets/:id/comments',
                                 params: { id: :integer, body: :string, private: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },

    # --- Datos personalizados (jabvox_customization) ---
    'create_custom_table' => { permission: 'create', method: :post, path: 'jabvox/custom_tables',
                               params: { name_jabvox: :string, description_jabvox: :string, kind_jabvox: :string },
                               mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'update_custom_table' => { permission: 'write', method: :patch, path: 'jabvox/custom_tables/:id',
                               params: { id: :integer, name_jabvox: :string, description_jabvox: :string, kind_jabvox: :string },
                               mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'create_custom_column' => { permission: 'create', method: :post, path: 'jabvox/custom_tables/:id/custom_columns',
                                params: { id: :integer, name_jabvox: :string, label_jabvox: :string, column_type_jabvox: :string,
                                          required_jabvox: :boolean, options_jabvox: :json, depends_on_jabvox: :string, show_when_jabvox: :json },
                                mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'update_custom_column' => { permission: 'write', method: :patch, path: 'jabvox/custom_tables/:id/custom_columns/:column_id',
                                params: { id: :integer, column_id: :integer, label_jabvox: :string, required_jabvox: :boolean,
                                          options_jabvox: :json, position_jabvox: :integer },
                                mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'create_custom_table_row' => { permission: 'create', method: :post, path: 'jabvox/custom_tables/:id/data',
                                   params: { id: :integer, data: :json }, mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'update_custom_table_row' => { permission: 'write', method: :patch, path: 'jabvox/custom_tables/:id/data/:row_id',
                                   params: { id: :integer, row_id: :integer, data: :json }, mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'create_quick_button' => { permission: 'create', method: :post, path: 'jabvox/quick_buttons',
                               params: { name_jabvox: :string, url_jabvox: :string, color_jabvox: :string, active_jabvox: :boolean },
                               mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'update_quick_button' => { permission: 'write', method: :patch, path: 'jabvox/quick_buttons/:id',
                               params: { id: :integer, name_jabvox: :string, url_jabvox: :string, color_jabvox: :string, active_jabvox: :boolean },
                               mcp: 'jabvox_core', feature: 'jabvox_customization' },

    # --- Productos (jabvox_products) ---
    'create_product' => { permission: 'create', method: :post, path: 'jabvox/products',
                          params: { name_jabvox: :string, description_jabvox: :string, price_jabvox: :string,
                                    tax_percentage_jabvox: :string, active_jabvox: :boolean, product_type_jabvox: :string,
                                    jabvox_currency_id: :integer, jabvox_item_type_id: :integer, jabvox_unit_of_measure_id: :integer },
                          mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_product' => { permission: 'write', method: :patch, path: 'jabvox/products/:id',
                          params: { id: :integer, name_jabvox: :string, description_jabvox: :string, price_jabvox: :string,
                                    tax_percentage_jabvox: :string, active_jabvox: :boolean, product_type_jabvox: :string,
                                    jabvox_currency_id: :integer, jabvox_item_type_id: :integer, jabvox_unit_of_measure_id: :integer },
                          mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_order' => { permission: 'create', method: :post, path: 'jabvox/orders',
                        params: { contact_id: :integer, conversation_id: :integer, doc_type: :string, status: :string,
                                  notes: :string, items: :json },
                        mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_order' => { permission: 'write', method: :patch, path: 'jabvox/orders/:id',
                        params: { id: :integer, doc_type: :string, status: :string, notes: :string, items: :json },
                        mcp: 'jabvox_core', feature: 'jabvox_products' },
    'send_order_to_alegra' => { permission: 'write', method: :post, path: 'jabvox/orders/:id/send_to_alegra',
                                params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_discount' => { permission: 'create', method: :post, path: 'jabvox/discounts',
                           params: { name_jabvox: :string, description_jabvox: :string, percentage_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_discount' => { permission: 'write', method: :patch, path: 'jabvox/discounts/:id',
                           params: { id: :integer, name_jabvox: :string, description_jabvox: :string, percentage_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_order_status_config' => { permission: 'create', method: :post, path: 'jabvox/order_status_configs',
                                      params: { key_jabvox: :string, label_jabvox: :string, sort_order_jabvox: :integer, color_jabvox: :string },
                                      mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_order_status_config' => { permission: 'write', method: :patch, path: 'jabvox/order_status_configs/:id',
                                      params: { id: :integer, key_jabvox: :string, label_jabvox: :string, sort_order_jabvox: :integer, color_jabvox: :string },
                                      mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_units_of_measure' => { permission: 'read', method: :get, path: 'jabvox/units_of_measure',
                                params: { active_jabvox: :boolean, limit: :integer },
                                mcp: 'jabvox_core', feature: 'core' },

    # --- Visibilidad de campos y extensiones de agente ---
    'get_field_visibilities' => { permission: 'read', method: :get, path: 'jabvox/field_visibilities',
                                  params: { user_id: :integer, field_name: :string, limit: :integer },
                                  mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'update_field_visibility' => { permission: 'write', method: :patch, path: 'jabvox/field_visibilities',
                                   params: { user_id: :integer, field_name: :string, can_view: :boolean },
                                   mcp: 'jabvox_core', feature: 'jabvox_customization' },
    'get_user_extensions' => { permission: 'read', method: :get, path: 'jabvox/user_extensions',
                               params: { user_id: :integer, limit: :integer }, mcp: 'jabvox_core', feature: 'jabvox_dialer' },
    'update_user_extension' => { permission: 'write', method: :patch, path: 'jabvox/user_extensions',
                                 params: { user_id: :integer, extension: :string },
                                 mcp: 'jabvox_core', feature: 'jabvox_dialer' },

    # --- Configuración de canales (solo lectura: nunca exponen credenciales) ---
    'get_smtp_config' => { permission: 'read', method: :get, path: 'jabvox/smtp_config',
                           mcp: 'jabvox_core', feature: 'jabvox_email' },
    'get_voip_config' => { permission: 'read', method: :get, path: 'jabvox/voip_config',
                           mcp: 'jabvox_core', feature: 'jabvox_dialer' },
    # --- Saldo IA / LiteLLM ---
    'get_ai_balance' => { permission: 'read', method: :get, path: 'jabvox/ai_balance',
                          mcp: 'jabvox_core', feature: 'jabvox_saldo' },
    'get_ai_balance_movements' => { permission: 'read', method: :get, path: 'jabvox/ai_balance/movements',
                                    params: { since: :string, until: :string, kind_jabvox: :string, limit: :integer },
                                    mcp: 'jabvox_core', feature: 'jabvox_saldo' },
    'refresh_ai_balance' => { permission: 'write', method: :post, path: 'jabvox/ai_balance/refresh',
                              mcp: 'jabvox_core', feature: 'jabvox_saldo' },
    'get_saldo_configs' => { permission: 'read', method: :get, path: 'jabvox/saldo_configs',
                             params: { limit: :integer }, mcp: 'jabvox_core', feature: 'jabvox_saldo' },
    # --- Lista blanca de IP ---
    'get_ip_whitelists' => { permission: 'read', method: :get, path: 'jabvox/ip_whitelists',
                             params: { is_active: :boolean, limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_ip_whitelist' => { permission: 'create', method: :post, path: 'jabvox/ip_whitelists',
                               params: { ip: :string, comment: :string, is_active: :boolean },
                               mcp: 'jabvox_core', feature: 'core' },
    'update_ip_whitelist' => { permission: 'write', method: :patch, path: 'jabvox/ip_whitelists/:id',
                               params: { id: :integer, ip: :string, comment: :string, is_active: :boolean },
                               mcp: 'jabvox_core', feature: 'core' },
    # --- Horarios de atención ---
    'get_working_hours' => { permission: 'read', method: :get, path: 'jabvox/working_hours',
                             params: { inbox_id: :integer, limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'update_working_hour' => { permission: 'write', method: :patch, path: 'jabvox/working_hours',
                               params: { inbox_id: :integer, day_of_week: :integer, closed_all_day: :boolean,
                                         open_all_day: :boolean, open_hour: :integer, open_minutes: :integer,
                                         close_hour: :integer, close_minutes: :integer },
                               mcp: 'jabvox_core', feature: 'core' },
    # --- Macros ---
    'get_macros' => { permission: 'read', method: :get, path: 'macros',
                      params: { visibility: :string, limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'get_macro' => { permission: 'read', method: :get, path: 'macros/:id',
                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_macro' => { permission: 'create', method: :post, path: 'macros',
                        params: { name: :string, visibility: :string, actions: :json },
                        mcp: 'jabvox_core', feature: 'core' },
    'update_macro' => { permission: 'write', method: :patch, path: 'macros/:id',
                        params: { id: :integer, name: :string, visibility: :string, actions: :json },
                        mcp: 'jabvox_core', feature: 'core' },
    # --- Equipos y agentes ---
    'get_teams' => { permission: 'read', method: :get, path: 'teams',
                     params: { limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'get_team' => { permission: 'read', method: :get, path: 'teams/:id',
                    params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_team' => { permission: 'create', method: :post, path: 'teams',
                       params: { name: :string, description: :string, allow_auto_assign: :boolean },
                       mcp: 'jabvox_core', feature: 'core' },
    'update_team' => { permission: 'write', method: :patch, path: 'teams/:id',
                       params: { id: :integer, name: :string, description: :string, allow_auto_assign: :boolean },
                       mcp: 'jabvox_core', feature: 'core' },
    'get_agents' => { permission: 'read', method: :get, path: 'agents',
                      params: { role: :string, limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    # --- Etiquetas de una conversación ---
    'get_conversation_labels' => { permission: 'read', method: :get, path: 'conversations/:id/labels',
                                   params: { id: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'add_conversation_label' => { permission: 'write', method: :post, path: 'conversations/:id/labels',
                                  params: { id: :integer, label: :string }, mcp: 'jabvox_core', feature: 'core' },
    'remove_conversation_label' => { permission: 'write', method: :patch, path: 'conversations/:id/labels/remove',
                                     params: { id: :integer, label: :string }, mcp: 'jabvox_core', feature: 'core' },
    # --- Kanban: tablero, tarjetas y automatizaciones de columna ---
    'get_kanban_stages' => { permission: 'read', method: :get, path: 'jabvox/kanban_stages',
                             params: { funnel_id: :integer, limit: :integer },
                             mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'get_kanban_board' => { permission: 'read', method: :get, path: 'jabvox/kanban_board',
                            params: { funnel_id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'get_kanban_stage_cards' => { permission: 'read', method: :get, path: 'jabvox/kanban_stages/:stage_id/cards',
                                  params: { stage_id: :integer, limit: :integer },
                                  mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'move_kanban_card' => { permission: 'write', method: :patch, path: 'jabvox/kanban_cards/move',
                            params: { conversation_id: :integer, stage_id: :integer },
                            mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'get_kanban_stage_automations' => { permission: 'read', method: :get, path: 'jabvox/kanban_stage_automations',
                                        params: { jabvox_kanban_stage_id: :integer, active: :boolean, limit: :integer },
                                        mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'create_kanban_stage_automation' => { permission: 'create', method: :post, path: 'jabvox/kanban_stage_automations',
                                          params: { stage_id: :integer, name: :string, automation_type: :string,
                                                    channel_type: :string, message_body: :string, inbox_id: :integer,
                                                    trigger_hours: :integer, target_stage_id: :integer,
                                                    email_template_id: :integer, sms_provider_id: :integer,
                                                    active: :boolean },
                                          mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'update_kanban_stage_automation' => { permission: 'write', method: :patch,
                                          path: 'jabvox/kanban_stage_automations/:id',
                                          params: { id: :integer, name: :string, automation_type: :string,
                                                    channel_type: :string, message_body: :string, inbox_id: :integer,
                                                    trigger_hours: :integer, target_stage_id: :integer,
                                                    email_template_id: :integer, sms_provider_id: :integer,
                                                    active: :boolean },
                                          mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    # --- Calendario: personas externas (listado) ---
    'get_calendar_external_people' => { permission: 'read', method: :get, path: 'jabvox/calendar/external_people',
                                        params: { limit: :integer }, mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    # --- Catálogos ---
    'get_typifications' => { permission: 'read', method: :get, path: 'jabvox/typifications',
                             params: { is_active: :boolean, limit: :integer }, mcp: 'jabvox_core', feature: 'core' },
    'create_typification' => { permission: 'create', method: :post, path: 'jabvox/typifications',
                               params: { name: :string, description: :string, is_active: :boolean },
                               mcp: 'jabvox_core', feature: 'core' },
    'update_typification' => { permission: 'write', method: :patch, path: 'jabvox/typifications/:id',
                               params: { id: :integer, name: :string, description: :string, is_active: :boolean },
                               mcp: 'jabvox_core', feature: 'core' },
    'get_currencies' => { permission: 'read', method: :get, path: 'jabvox/currencies',
                          params: { active_jabvox: :boolean, limit: :integer },
                          mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_sms_providers' => { permission: 'read', method: :get, path: 'jabvox/sms_providers',
                             params: { active: :boolean, limit: :integer }, mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'get_sms_messages' => { permission: 'read', method: :get, path: 'jabvox/sms_messages',
                            params: { jabvox_sms_campaign_id: :integer, status: :string, contact_id: :integer,
                                      since: :string, until: :string, limit: :integer },
                            mcp: 'jabvox_sms', feature: 'jabvox_sms' }
  }.freeze

  # Métodos HTTP y permisos prohibidos por política. Ninguna tool puede borrar.
  FORBIDDEN_METHODS = %i[delete].freeze
  FORBIDDEN_PERMISSIONS = %w[delete destroy].freeze

  # Garantiza en tiempo de carga que ninguna tool sea destructiva. Falla ruidosamente si
  # alguien introduce una tool :delete: la seguridad no depende de recordar la política.
  def assert_no_destructive_tools!
    offenders = TOOLS.select do |_name, spec|
      FORBIDDEN_METHODS.include?(spec[:method]) ||
        FORBIDDEN_PERMISSIONS.include?(spec[:permission])
    end
    return if offenders.empty?

    raise "Tools destructivas prohibidas en ToolRegistry: #{offenders.keys.join(', ')}"
  end

  # Features de módulo válidos (los que Account#feature_enabled? reconoce). 'core' es
  # funcionalidad base (labels, contactos, conversaciones): no gatea por módulo.
  VALID_FEATURES = %w[
    core
    jabvox_advanced_automations jabvox_affiliates jabvox_ai_chat jabvox_ai_chat_provisioning
    jabvox_analytics jabvox_audio_analysis jabvox_bulk_whatsapp jabvox_calendar jabvox_call_source
    jabvox_cdr jabvox_click_to_call jabvox_customization jabvox_data_export jabvox_dialer
    jabvox_email jabvox_forms jabvox_internal_chat jabvox_kanban
    jabvox_lead_import jabvox_products jabvox_saldo jabvox_sms
    jabvox_softphone jabvox_tasks jabvox_tickets jabvox_voice_broadcast jabvox_voip
    jabvox_whatsapp_groups jabvox_whatsapp_templates
  ].freeze

  # Falla en tiempo de carga si alguna tool declara un `feature:` que Account no reconoce:
  # un feature mal escrito haría que feature_enabled? explote (NoMethodError) al autorizar,
  # dejando la tool inaccesible en silencio. Se detecta aquí, no en producción.
  def assert_valid_features!
    offenders = TOOLS.reject do |_name, spec|
      spec[:feature].blank? || VALID_FEATURES.include?(spec[:feature])
    end
    return if offenders.empty?

    detail = offenders.map { |n, s| "#{n} (feature: #{s[:feature]})" }.join(', ')
    raise "Features desconocidos en ToolRegistry: #{detail}"
  end

  def all
    TOOLS
  end

  def find(tool_name)
    TOOLS[tool_name.to_s]
  end

  def exists?(tool_name)
    TOOLS.key?(tool_name.to_s)
  end

  # Descripción legible por tool (para que el LLM sepa cuándo usarla). Si falta,
  # se deriva del nombre.
  DESCRIPTIONS = {
    'get_labels' => 'Lista las etiquetas de la cuenta.',
    'create_label' => 'Crea una etiqueta nueva.',
    'update_label' => 'Renombra una etiqueta existente.',
    'get_inboxes' => 'Lista las bandejas de entrada.',
    'search_contacts' => 'Busca contactos por texto (nombre, email o teléfono).',
    'get_contact' => 'Obtiene un contacto por su id.',
    'create_contact' => 'Crea un contacto.',
    'update_contact' => 'Actualiza un contacto.',
    'get_conversations_meta' => 'Devuelve conteos de conversaciones (abiertas/total).',
    'list_conversations' => 'Lista conversaciones con filtros (estado, bandeja, contacto) y paginación.',
    'get_conversation_messages' => 'Devuelve los mensajes de una conversación.',
    'summarize_conversation' => 'Devuelve el material (metadatos + mensajes) de una conversación para resumirla.',
    'reply_conversation' => 'Envía una respuesta al cliente en una conversación.',
    'add_private_note' => 'Agrega una nota privada (interna) a una conversación.',
    'get_orders' => 'Lista pedidos/cotizaciones (módulo Productos).',
    'get_audio_jobs' => 'Lista trabajos de análisis de audio (módulo Análisis de Audio).',
    'get_analytics_data_sources' => 'Lista las fuentes de datos externas (módulo Analytics).',
    'get_analytics_data_source' => 'Obtiene una fuente de datos externa por id (sin exponer credenciales).',
    'get_analytics_data_source_schema' => 'Lista las tablas/columnas de una fuente de datos externa (introspección).',
    'run_analytics_query' => 'Ejecuta SQL de SOLO LECTURA contra una fuente de datos externa (por id). Rechaza INSERT/UPDATE/DELETE/DROP. Hermes NO pasa credenciales: van cifradas en la fuente.',
    'preview_analytics_table' => 'Previsualiza filas de una tabla de una fuente de datos externa (paginado).',
    'get_analytics_dashboards' => 'Lista los dashboards de Analytics de la cuenta.',
    'get_analytics_dashboard' => 'Obtiene un dashboard por id con sus widgets.',
    'create_analytics_dashboard' => 'Crea un dashboard vacío (name obligatorio; description y folder_id opcionales). Luego añade widgets con create_analytics_widget.',
    'update_analytics_dashboard' => 'Edita un dashboard (name, description, folder_id).',
    'create_analytics_widget' => 'Añade un widget a un dashboard usando una fuente de datos YA conectada. ' \
                                 'Pasa dashboard_id, title, widget_type (table|number|indicator|bar|line|area|' \
                                 'pie|donut|ranking|gauge...), data_source_id y custom_sql (SQL read-only) o query_spec.',
    'update_analytics_widget' => 'Edita un widget existente (title, widget_type, data_source_id, custom_sql, query_spec, config).',
    'execute_analytics_widget' => 'Ejecuta un widget guardado y devuelve sus columnas y filas (read-only).',
    'get_analytics_folders' => 'Lista las carpetas de dashboards de Analytics.',
    'create_analytics_folder' => 'Crea una carpeta para organizar dashboards (name).',
    'update_analytics_folder' => 'Renombra una carpeta de dashboards.',
    'get_analytics_cross_reports' => 'Lista los reportes cruzados (unen datos de varias BD externas).',
    'get_analytics_cross_report' => 'Obtiene un reporte cruzado por id.',
    'execute_analytics_cross_report' => 'Ejecuta un reporte cruzado guardado y devuelve columnas y filas (read-only).',
    'get_analytics_overview_stats' => 'Resumen del módulo Analytics (nº de dashboards, fuentes, carpetas).',
    'get_analytics_internal_reports' => 'Lista los reportes internos pre-armados disponibles.',
    'get_agents_report' => 'Reporte de agentes (mensajes, notas, gestiones, pedidos) en un rango de fechas (since/until).',
    'get_products_report' => 'Reporte de productos/pedidos: totales, monto, por estado y tipo de documento (since/until).',
    'get_dialer_report' => 'Reporte del marcador: llamadas totales, contestadas, duración y por estado (since/until). Solo datos, no toca telefonía.',
    'get_agent_status_report' => 'Estado en vivo de los agentes (conectados/desconectados).',
    'get_hermes_activity_report' => 'Reporte de actividad de Hermes: acciones por estado y por herramienta (since/until).',
    'get_tasks' => 'Lista tareas (módulo Tareas).',
    'get_calendar_events' => 'Lista eventos del calendario (módulo Calendario).',
    # Automatizaciones básicas (reglas)
    'get_automation_rules' => 'Lista las automatizaciones básicas (reglas de la cuenta).',
    'get_automation_rule' => 'Obtiene una automatización básica por su id (condiciones y acciones).',
    'create_automation_rule' => 'Crea una automatización básica: name, event_name (p.ej. conversation_created), conditions [] y actions [].',
    'update_automation_rule' => 'Edita una automatización básica (nombre, condiciones, acciones, o active para activar/desactivar).',
    'toggle_automation_rule' => 'Activa o desactiva una automatización básica (active: true/false).',
    'clone_automation_rule' => 'Clona una automatización básica existente (crea una copia).',
    # Automatizaciones avanzadas (flujos)
    'get_flows' => 'Lista las automatizaciones avanzadas (flujos) de la cuenta.',
    'get_flow' => 'Obtiene un flujo avanzado por su id (con su grafo/versión actual).',
    'create_flow' => 'Crea un flujo avanzado vacío (name, description, folder_id). El grafo se diseña luego en el editor.',
    'update_flow' => 'Edita los datos de un flujo avanzado (nombre, descripción, carpeta).',
    'set_flow_status' => 'Cambia el estado de un flujo avanzado: draft, active (activar), paused (pausar) o archived. Activar exige que el grafo pase la validación.',
    'duplicate_flow' => 'Duplica un flujo avanzado (crea uno nuevo con el mismo grafo).',
    'validate_flow' => 'Valida el grafo de un flujo avanzado y devuelve los problemas encontrados (sin activarlo).',
    'run_flow' => 'Ejecuta manualmente un flujo avanzado (prueba); se encola y devuelve el id del run.',
    'get_flow_node_types' => 'Lista los tipos de nodo disponibles para construir flujos (triggers, lógica, acciones Jabvox, integraciones).',
    'save_flow_graph' => 'Guarda el grafo de un flujo: nodes [] y edges [] (conexiones). Valida antes; crea una versión nueva. Usa get_flow_node_types para conocer los tipos y sus parámetros.',
    'test_flow_node' => 'Prueba un nodo concreto del flujo (node_id) de forma aislada, sin activar el flujo; opcional prior_outputs con salidas previas simuladas.',
    # WhatsApp templates y masivos
    'get_whatsapp_templates' => 'Lista las plantillas de WhatsApp de la cuenta.',
    'create_whatsapp_template' => 'Crea una plantilla de WhatsApp: name, category, language, inbox_id, body y opcionales header/footer/buttons.',
    'update_whatsapp_template' => 'Edita una plantilla de WhatsApp.',
    'duplicate_whatsapp_template' => 'Duplica una plantilla de WhatsApp existente.',
    'sync_whatsapp_template' => 'Sincroniza el estado de una plantilla de WhatsApp con Meta/proveedor.',
    'send_whatsapp_template_to_contact' => 'Envía una plantilla de WhatsApp APROBADA a un contacto (template_id + contact_id). La plantilla debe estar aprobada por Meta y el contacto tener teléfono.',
    'create_task' => 'Crea una tarea. title_jabvox obligatorio. priority_jabvox: low/normal/high/urgent (no "medium"). status_jabvox: open/done. Si no indicas board_id/stage_id se usan los primeros de la cuenta.',
    'create_calendar_event' => 'Crea un evento de calendario (title, start_at, end_at). El módulo no tiene campo responsable; usa la nota para indicarlo.',
    'get_bulk_whatsapp_batches' => 'Lista los lotes de envío masivo de WhatsApp.',
    'reuse_bulk_whatsapp_batch' => 'Reutiliza (reenvía) un lote de envío masivo de WhatsApp previo.',

    # --- Descripciones completas del resto del catálogo (para el system prompt) ---
    # Núcleo
    'get_webhooks' => 'Lista los webhooks configurados en la cuenta.',
    'get_contact_notes' => 'Lista las notas de un contacto (por id de contacto).',
    'create_contact_note' => 'Añade una nota a un contacto (content).',
    'create_hermes_webhook' => 'Crea/asegura el webhook a nivel de cuenta hacia el propio Hermes (message_created).',
    'create_hermes_inbox_webhook' => 'Crea/asegura el webhook de UNA bandeja (inbox_id) hacia el propio Hermes.',
    'create_api_inbox' => 'Crea una bandeja de tipo API (name, webhook_url).',
    'get_management_states' => 'Lista los estados de gestión de la cuenta.',
    'create_management_state' => 'Crea un estado de gestión (name).',
    'update_management_state' => 'Edita un estado de gestión.',
    'export_management_states' => 'Exporta la definición de los estados de gestión.',
    'get_report_summary' => 'Resumen del reporte de agentes (mensajes, notas, gestiones).',
    'assign_conversation' => 'Asigna una conversación a un agente (assignee_id) y/o equipo (team_id).',
    'update_conversation_status' => 'Cambia el estado de una conversación: open/resolved/pending/snoozed (snoozed_until).',
    # Leads avanzado
    'get_campaigns' => 'Lista las campañas de leads de la cuenta.',
    # Análisis de audio
    'get_audio_job' => 'Obtiene un trabajo de análisis de audio por id.',
    'get_audio_pipelines' => 'Lista los pipelines de análisis de audio.',
    # Reportes CDR
    'get_cdr_records' => 'Lista los registros de llamadas del CDR (reportes de telefonía, solo lectura).',
    'sync_cdr_now' => 'Dispara una sincronización del CDR ahora (importa registros nuevos).',
    'analyze_cdr_call' => 'Analiza una llamada del CDR (uniqueid) con un pipeline de audio.',
    'typify_cdr_call' => 'Tipifica una llamada del CDR (uniqueid + typification_id).',
    # Click to call
    'get_click_to_call_logs' => 'Lista los registros de llamadas click-to-call (solo lectura).',
    'typify_click_to_call' => 'Tipifica una llamada click-to-call (typification_id + nota).',
    # Marcador (gestión de campañas; NUNCA telefonía cruda/AMI)
    'get_dialer_campaigns' => 'Lista las campañas del marcador.',
    'get_dialer_campaign' => 'Obtiene una campaña del marcador por id.',
    'get_dialer_campaign_progress' => 'Progreso de una campaña del marcador (avance, contactados).',
    'get_dialer_call_logs' => 'Lista los registros de llamadas del marcador (solo lectura).',
    'get_dialer_states' => 'Lista los estados/pausas del marcador.',
    'create_dialer_campaign' => 'Crea una campaña del marcador (name). No origina llamadas: eso lo hace el backend.',
    'update_dialer_campaign' => 'Edita una campaña del marcador.',
    'create_dialer_state' => 'Crea un estado/pausa del marcador (name, color, posición).',
    'update_dialer_state' => 'Edita un estado/pausa del marcador.',
    'import_dialer_contacts' => 'Importa contactos a una campaña del marcador (lista contacts).',
    'start_dialer_campaign' => 'Inicia una campaña del marcador (el backend gestiona la marcación).',
    'pause_dialer_campaign' => 'Pausa una campaña del marcador.',
    'stop_dialer_campaign' => 'Detiene una campaña del marcador.',
    'retry_dialer_campaign' => 'Reintenta los contactos pendientes de una campaña.',
    'exclude_dialer_lead' => 'Excluye un contacto de una campaña del marcador.',
    'redial_dialer_lead' => 'Marca un contacto para volver a llamar en una campaña.',
    'typify_dialer_call' => 'Tipifica una llamada del marcador (typification_id + notas).',
    # Importar leads / exportar datos (BD externa)
    'get_lead_import_sources' => 'Lista las fuentes de importación de leads (BD externas, solo lectura).',
    'get_lead_import_source' => 'Obtiene una fuente de importación de leads por id (sin credenciales).',
    'trigger_lead_import_sync' => 'Dispara la importación de leads desde una fuente externa (lectura read-only de esa BD).',
    'get_lead_import_sync_status' => 'Estado de la última importación de leads de una fuente.',
    'get_data_export_targets' => 'Lista los destinos de exportación de datos.',
    'get_data_export_target' => 'Obtiene un destino de exportación por id (sin credenciales).',
    'trigger_data_export_sync' => 'Dispara la exportación de datos hacia un destino externo.',
    # Productos y pedidos
    'get_products' => 'Lista los productos de la cuenta.',
    'get_product' => 'Obtiene un producto por id.',
    'create_product' => 'Crea un producto (nombre, precio, impuesto, moneda, tipo, unidad).',
    'update_product' => 'Edita un producto.',
    'get_order' => 'Obtiene un pedido/cotización por id.',
    'create_order' => 'Crea un pedido/cotización (contacto, tipo de documento, ítems).',
    'update_order' => 'Edita un pedido/cotización (estado, notas, ítems).',
    'send_order_to_alegra' => 'Envía un pedido a Alegra (facturación).',
    'create_currency' => 'Crea una moneda (símbolo, nombre).',
    'create_discount' => 'Crea un descuento (nombre, porcentaje).',
    'update_discount' => 'Edita un descuento.',
    'create_item_type' => 'Crea un tipo de ítem.',
    'update_item_type' => 'Edita un tipo de ítem.',
    'create_tax_rate' => 'Crea una tasa de impuesto (nombre, porcentaje).',
    'update_tax_rate' => 'Edita una tasa de impuesto.',
    'create_unit_of_measure' => 'Crea una unidad de medida (nombre, abreviatura).',
    'create_order_status_config' => 'Crea un estado de pedido (clave, etiqueta, color).',
    'update_order_status_config' => 'Edita un estado de pedido.',
    # Tareas
    'get_task_boards' => 'Lista los tableros de tareas.',
    'update_task' => 'Edita una tarea (título, etapa, responsable, prioridad, estado, vencimiento).',
    'move_task' => 'Mueve una tarea a otra etapa/posición.',
    'create_task_board' => 'Crea un tablero de tareas.',
    'update_task_board' => 'Edita un tablero de tareas.',
    'create_task_stage' => 'Crea una etapa dentro de un tablero de tareas.',
    'update_task_stage' => 'Edita una etapa de tareas.',
    # Tickets
    'get_tickets' => 'Lista los tickets de la cuenta.',
    'get_ticket' => 'Obtiene un ticket por id.',
    'get_ticket_comments' => 'Lista los comentarios de un ticket.',
    'create_ticket' => 'Crea un ticket (título, descripción, categoría, prioridad).',
    'update_ticket' => 'Edita un ticket.',
    'create_ticket_comment' => 'Añade un comentario a un ticket (private opcional).',
    'assign_ticket' => 'Asigna un ticket a un agente.',
    'change_ticket_status' => 'Cambia el estado de un ticket.',
    'resolve_ticket' => 'Resuelve un ticket (resolución + tipo).',
    'reopen_ticket' => 'Reabre un ticket resuelto.',
    'rate_ticket' => 'Califica un ticket (rating + comentario).',
    'merge_ticket' => 'Fusiona un ticket dentro de otro (target_id).',
    # Kanban
    'get_kanban_funnels' => 'Lista los embudos (funnels) de Kanban.',
    'create_kanban_funnel' => 'Crea un embudo de Kanban.',
    'update_kanban_funnel' => 'Edita un embudo de Kanban.',
    'create_kanban_stage' => 'Crea una etapa dentro de un embudo de Kanban.',
    'update_kanban_stage' => 'Edita una etapa de Kanban.',
    # Correo
    'get_email_templates' => 'Lista las plantillas de correo.',
    'create_email_template' => 'Crea una plantilla de correo (nombre, asunto, cuerpo).',
    'update_email_template' => 'Edita una plantilla de correo.',
    'send_email_template_to_contact' => 'Envía una plantilla de correo a un contacto.',
    'test_send_email_template' => 'Envía una prueba de una plantilla de correo a una dirección (to).',
    # Formularios
    'get_forms' => 'Lista los formularios de la cuenta.',
    'get_form' => 'Obtiene un formulario por id.',
    'create_form' => 'Crea un formulario (nombre, slug, campos).',
    'update_form' => 'Edita un formulario.',
    # Chat interno
    'get_internal_chats' => 'Lista los chats internos de equipo del usuario.',
    'create_internal_chat' => 'Crea un chat interno de equipo (directo o grupal, miembros).',
    'send_internal_chat_message' => 'Envía un mensaje a un chat interno.',
    'mark_internal_chat_read' => 'Marca un chat interno como leído.',
    # SMS
    'get_sms_campaigns' => 'Lista las campañas de SMS.',
    'create_sms_campaign' => 'Crea una campaña de SMS (nombre, mensaje).',
    'update_sms_campaign' => 'Edita una campaña de SMS.',
    # Datos personalizados
    'get_custom_tables' => 'Lista las tablas de datos personalizados.',
    'create_custom_table' => 'Crea una tabla de datos personalizados (nombre, tipo).',
    'update_custom_table' => 'Edita una tabla de datos personalizados.',
    'create_custom_column' => 'Crea una columna en una tabla personalizada (nombre, tipo, opciones).',
    'update_custom_column' => 'Edita una columna de una tabla personalizada.',
    'create_custom_table_row' => 'Crea una fila (registro) en una tabla personalizada (data).',
    'update_custom_table_row' => 'Edita una fila de una tabla personalizada.',
    'create_quick_button' => 'Crea un botón rápido (nombre, url, color).',
    'update_quick_button' => 'Edita un botón rápido.',
    # Calendario
    'create_calendar_external_person' => 'Crea una persona externa del calendario (nombre, email, teléfono).',
    'update_calendar_external_person' => 'Edita una persona externa del calendario.',
    'update_calendar_event' => 'Edita un evento del calendario.',
    # Afiliados
    'get_affiliates' => 'Lista los afiliados de la cuenta.',
    'create_affiliate' => 'Crea un afiliado (nombre).',
    'update_affiliate' => 'Edita un afiliado.',
    'regenerate_affiliate_code' => 'Regenera el código de un afiliado.',
    'get_ai_balance' => 'Saldo de IA de la cuenta (LiteLLM): presupuesto del plan, saldo comprado, gasto y disponible.',
    'get_ai_balance_movements' => 'Movimientos del saldo de IA (recargas, consumo, ajustes) en un rango de fechas (since/until).',
    'refresh_ai_balance' => 'Relee el gasto de IA contra el proveedor y devuelve el saldo actualizado. No mueve dinero.',
    'get_saldo_configs' => 'Configuraciones de saldo del panel (sin credenciales).',
    'get_ip_whitelists' => 'Lista blanca de IPs autorizadas de la cuenta.',
    'create_ip_whitelist' => 'Autoriza una IP nueva (ip, comentario).',
    'update_ip_whitelist' => 'Edita una IP autorizada. Para retirarla usa is_active: false (no se borra).',
    'get_working_hours' => 'Horario de atención por bandeja y día (0=domingo … 6=sábado).',
    'update_working_hour' => 'Cambia el horario de UN día de una bandeja (inbox_id + day_of_week).',
    'get_macros' => 'Macros de la cuenta (secuencias de acciones reutilizables).',
    'get_macro' => 'Detalle de una macro con sus acciones.',
    'create_macro' => 'Crea una macro (name, visibility: global|personal, actions).',
    'update_macro' => 'Edita una macro.',
    'get_teams' => 'Equipos de la cuenta.',
    'get_team' => 'Detalle de un equipo con sus miembros.',
    'create_team' => 'Crea un equipo.',
    'update_team' => 'Edita un equipo.',
    'get_agents' => 'Agentes de la cuenta con su rol y disponibilidad — para saber a quién asignar.',
    'get_conversation_labels' => 'Etiquetas de una conversación, con desde cuándo las tiene (days_applied).',
    'add_conversation_label' => 'Pone una etiqueta a una conversación.',
    'remove_conversation_label' => 'Quita una etiqueta de una conversación (la etiqueta sigue existiendo en la cuenta).',
    'get_kanban_stages' => 'Columnas de un embudo kanban, con su orden y auto-avance.',
    'get_kanban_board' => 'Vista del tablero kanban: cada columna con cuántas tarjetas tiene.',
    'get_kanban_stage_cards' => 'Conversaciones colocadas en una columna del kanban, con contacto y estado.',
    'move_kanban_card' => 'Mueve una conversación a otra columna del embudo (queda registrado quién la movió).',
    'get_kanban_stage_automations' => 'Automatizaciones configuradas en las columnas del kanban.',
    'create_kanban_stage_automation' => 'Crea una automatización de columna. automation_type: send_message | move_after_hours | move_if_inactive. channel_type (solo con send_message): inbox | email | sms.',
    'update_kanban_stage_automation' => 'Edita una automatización de columna (mismos valores que create). Para desactivarla usa active: false.',
    'get_calendar_external_people' => 'Personas externas registradas en el calendario.',
    'get_typifications' => 'Tipificaciones de la cuenta.',
    'create_typification' => 'Crea una tipificación.',
    'update_typification' => 'Edita una tipificación. Para retirarla usa is_active: false.',
    'get_currencies' => 'Monedas configuradas.',
    'update_currency' => 'Edita una moneda.',
    'get_units_of_measure' => 'Unidades de medida configuradas.',
    'update_unit_of_measure' => 'Edita una unidad de medida.',
    'get_field_visibilities' => 'Qué campos puede ver cada agente.',
    'update_field_visibility' => 'Cambia si un agente puede ver un campo (user_id, field_name, can_view).',
    'get_user_extensions' => 'Extensión SIP de cada agente — a qué extensión marcar.',
    'update_user_extension' => 'Asigna o cambia la extensión SIP de un agente.',
    'get_smtp_config' => 'Configuración SMTP de la cuenta (sin la contraseña: solo has_password).',
    'get_voip_config' => 'Configuración VoIP/Asterisk de la cuenta (sin la contraseña).',
    'get_sms_providers' => 'Proveedores SMS configurados (sin credenciales).',
    'get_sms_messages' => 'Mensajes SMS enviados, con filtros por campaña, estado y rango de fechas.',
    'regenerate_affiliate_token' => 'Regenera el token de un afiliado.',
    # WhatsApp Masivo
    'get_bulk_whatsapp_batch' => 'Obtiene un lote de envío masivo de WhatsApp por id (estado, total, enviados).',
    'create_bulk_whatsapp_batch' => 'Crea y LANZA un envío masivo de WhatsApp a leads (envía mensajes reales). Pasa inbox_id, sender_user_id, template_name+language o text; leads con all+filters o lead_ids. variable_map mapea {{n}} a campos del lead.',
    # WhatsApp Grupos
    'get_whatsapp_groups' => 'Lista los grupos de WhatsApp de la cuenta.',
    'get_whatsapp_group' => 'Obtiene un grupo de WhatsApp por id, con sus miembros.',
    'create_whatsapp_group' => 'Crea un grupo de WhatsApp (inbox_id, name, description, member_phones []).',
    'update_whatsapp_group' => 'Edita el nombre/descripción de un grupo de WhatsApp.',
    'add_whatsapp_group_member' => 'Añade un miembro (phone) a un grupo de WhatsApp.',
    'send_whatsapp_group_message' => 'Envía un mensaje de texto a un grupo de WhatsApp.',
    # Voice Broadcast (gestión de campañas de audio; NO toca AMI/telefonía cruda)
    'get_voice_broadcasts' => 'Lista las campañas de Voice Broadcast (audio pregrabado).',
    'get_voice_broadcast' => 'Obtiene una campaña de Voice Broadcast por id (configuración).',
    'get_voice_broadcast_report' => 'Reporte de una campaña de Voice Broadcast: destinatarios, marcados, contestados (humano/máquina), reproducidos, fallidos.',
    'create_voice_broadcast' => 'Crea una campaña de Voice Broadcast (name, caller_id, concurrencia, cps, reintentos, ventana horaria, filtros de leads). El audio se sube desde la interfaz.',
    'update_voice_broadcast' => 'Edita la configuración de una campaña de Voice Broadcast.',
    'start_voice_broadcast' => 'Inicia una campaña de Voice Broadcast (exige audio desplegado). El backend hace la marcación; Hermes no toca AMI.',
    'pause_voice_broadcast' => 'Pausa una campaña de Voice Broadcast en curso.',
    'resume_voice_broadcast' => 'Reanuda una campaña de Voice Broadcast pausada.',
    'stop_voice_broadcast' => 'Detiene una campaña de Voice Broadcast.'
  }.freeze

  # Genera la definición de una tool en formato "function calling" compatible con
  # OpenAI/Hermes: name, description y JSON Schema de parámetros.
  def describe(tool_name)
    spec = find(tool_name)
    return nil unless spec

    props = (spec[:params] || {}).transform_values { |t| { type: json_type(t) } }
    {
      type: 'function',
      function: {
        name: tool_name,
        description: DESCRIPTIONS[tool_name] || tool_name.tr('_', ' '),
        parameters: { type: 'object', properties: props, required: required_params(spec) }
      }
    }
  end

  # Parámetros REALMENTE obligatorios: los que el path interpola (`conversations/:id/messages`
  # necesita `id`) y, para una búsqueda, su texto.
  #
  # Antes se marcaban TODOS como required, así que una tool de listado con filtros opcionales
  # (list_conversations: status, inbox_id, contact_id, before_id, limit) le pedía al modelo los
  # cinco. Ante esa exigencia imposible el LLM improvisaba nombres de parámetro —
  # `query` en vez de `q`, `conversation_id` en vez de `id` — y el handler, que solo acepta los
  # de la whitelist, los ignoraba y devolvía la lista SIN FILTRAR. De ahí que el agente
  # "no encontrara" un contacto que sí existe.
  # Campos sin los que una escritura no tiene sentido (create_label sin `title`, o
  # reply_conversation sin `content`, fallan en el handler). Se marcan obligatorios solo en
  # POST/PUT/PATCH: en un GET los mismos nombres son filtros de búsqueda opcionales.
  WRITE_REQUIRED_PARAMS = %w[title content name].freeze
  WRITE_METHODS = %i[post put patch].freeze

  def required_params(spec)
    names = (spec[:params] || {}).keys.map(&:to_s)
    required = names & spec[:path].to_s.scan(/:(\w+)/).flatten
    required |= ['q'] if names.include?('q')
    required |= (names & WRITE_REQUIRED_PARAMS) if WRITE_METHODS.include?(spec[:method])
    required
  end

  def json_type(type)
    case type
    when :integer then 'integer'
    when :boolean then 'boolean'
    when :json then 'object'
    else 'string'
    end
  end

  # Permiso requerido por una tool (o nil si no existe).
  def permission_for(tool_name)
    find(tool_name)&.fetch(:permission, nil)
  end

  # MCP lógico al que pertenece la tool (para el gating por cuenta).
  def mcp_for(tool_name)
    find(tool_name)&.fetch(:mcp, nil)
  end
end
