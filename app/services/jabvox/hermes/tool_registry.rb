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
                        params: { id: :integer, title: :string }, mcp: 'jabvox_core', feature: 'core' },

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
                                  mcp: 'jabvox_core', feature: 'core' },
    # Lista conversaciones con filtros (estado, inbox, contacto) y paginación por cursor.
    'list_conversations' => { permission: 'read', method: :get, path: 'conversations',
                              params: { status: :string, inbox_id: :integer, contact_id: :integer,
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

    # --- Leads (módulo leads) ---
    'search_leads' => { permission: 'read', method: :get, path: 'jabvox/leads',
                        params: { q: :string }, mcp: 'jabvox_leads', feature: 'core' },
    'get_lead' => { permission: 'read', method: :get, path: 'jabvox/leads/:id',
                    params: { id: :integer }, mcp: 'jabvox_leads', feature: 'core' },

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
                             mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'create_sms_campaign' => { permission: 'create', method: :post, path: 'jabvox/sms_campaigns',
                               params: { name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },
    'update_sms_campaign' => { permission: 'write', method: :patch, path: 'jabvox/sms_campaigns/:id',
                               params: { id: :integer, name: :string, message: :string },
                               mcp: 'jabvox_sms', feature: 'jabvox_sms' },

    # --- Reportes de la cuenta (solo lectura) ---
    'get_report_summary' => { permission: 'read', method: :get, path: 'jabvox/reports/agents',
                              mcp: 'analytics', feature: 'core' },

    # --- Análisis de Audio (módulo jabvox_audio_analysis) ---
    'get_audio_jobs' => { permission: 'read', method: :get, path: 'jabvox/audio/jobs',
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
                        mcp: 'jabvox_core', feature: 'jabvox_products' },
    'get_product' => { permission: 'read', method: :get, path: 'jabvox/products/:id',
                       params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_products' },

    # --- Tareas (módulo jabvox_tasks) ---
    'get_tasks' => { permission: 'read', method: :get, path: 'jabvox/tasks',
                     mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'get_task_boards' => { permission: 'read', method: :get, path: 'jabvox/tasks/boards',
                           mcp: 'jabvox_core', feature: 'jabvox_tasks' },

    # --- Calendario (módulo jabvox_calendar) ---
    'get_calendar_events' => { permission: 'read', method: :get, path: 'jabvox/calendar/events',
                               mcp: 'jabvox_core', feature: 'jabvox_calendar' },

    # --- Tickets (módulo jabvox_tickets) ---
    'get_tickets' => { permission: 'read', method: :get, path: 'jabvox/tickets',
                       mcp: 'jabvox_core', feature: 'jabvox_tickets' },
    'get_ticket' => { permission: 'read', method: :get, path: 'jabvox/tickets/:id',
                      params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_tickets' },

    # --- Kanban (módulo jabvox_kanban) ---
    'get_kanban_funnels' => { permission: 'read', method: :get, path: 'jabvox/kanban_funnels',
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
    # Envío masivo de WhatsApp: reutilizar un lote previo (reenvío controlado).
    'reuse_bulk_whatsapp_batch' => { permission: 'create', method: :post, path: 'jabvox/bulk_whatsapp/batches/:id/reuse',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },

    # --- Afiliados (módulo jabvox_affiliates) ---
    'get_affiliates' => { permission: 'read', method: :get, path: 'jabvox/affiliates',
                          mcp: 'jabvox_core', feature: 'jabvox_affiliates' },

    # --- Campañas de leads (gateadas por el módulo jabvox_leads) ---
    'get_campaigns' => { permission: 'read', method: :get, path: 'jabvox/campaigns',
                         mcp: 'jabvox_core', feature: 'jabvox_leads' },

    # --- CDR (módulo jabvox_cdr) ---
    'get_cdr_records' => { permission: 'read', method: :get, path: 'jabvox/cdr/records',
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
                       params: { title_jabvox: :string, board_id: :integer, stage_id: :integer, jabvox_lead_id: :integer,
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
    'create_task_lead_contact' => { permission: 'create', method: :post, path: 'jabvox/task_lead_contacts',
                                    params: { jabvox_lead_id: :integer, name_jabvox: :string, role_jabvox: :string,
                                              email_jabvox: :string, phone_jabvox: :string, description_jabvox: :string, position_jabvox: :integer },
                                    mcp: 'jabvox_core', feature: 'jabvox_tasks' },
    'update_task_lead_contact' => { permission: 'write', method: :patch, path: 'jabvox/task_lead_contacts/:id',
                                    params: { id: :integer, name_jabvox: :string, role_jabvox: :string, email_jabvox: :string,
                                              phone_jabvox: :string, description_jabvox: :string, position_jabvox: :integer },
                                    mcp: 'jabvox_core', feature: 'jabvox_tasks' },

    # --- Calendario (jabvox_calendar) ---
    'create_calendar_event' => { permission: 'create', method: :post, path: 'jabvox/calendar/events',
                                 params: { title: :string, start_at: :string, end_at: :string, all_day: :boolean,
                                           description: :string, note: :string, event_type: :string, status: :string,
                                           color: :string, contact_id: :integer },
                                 mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'update_calendar_event' => { permission: 'write', method: :patch, path: 'jabvox/calendar/events/:id',
                                 params: { id: :integer, title: :string, description: :string, note: :string,
                                           event_type: :string, status: :string, color: :string, contact_id: :integer },
                                 mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'create_calendar_external_person' => { permission: 'create', method: :post, path: 'jabvox/calendar/external_people',
                                           params: { name: :string, email: :string, phone_number: :string, notes: :string, color: :string },
                                           mcp: 'jabvox_core', feature: 'jabvox_calendar' },
    'update_calendar_external_person' => { permission: 'write', method: :patch, path: 'jabvox/calendar/external_people/:id',
                                           params: { id: :integer, name: :string, email: :string, phone_number: :string, notes: :string, color: :string },
                                           mcp: 'jabvox_core', feature: 'jabvox_calendar' },

    # --- Chat interno de equipo (jabvox_internal_chat) ---
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
                                          active_jabvox: :boolean, include_own_leads_jabvox: :boolean },
                                mcp: 'jabvox_core', feature: 'jabvox_kanban' },
    'update_kanban_funnel' => { permission: 'write', method: :patch, path: 'jabvox/kanban_funnels/:id',
                                params: { id: :integer, name_jabvox: :string, description_jabvox: :string, position_jabvox: :integer,
                                          active_jabvox: :boolean, include_own_leads_jabvox: :boolean },
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
    'create_currency' => { permission: 'create', method: :post, path: 'jabvox/currencies',
                           params: { symbol_jabvox: :string, name_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_currency' => { permission: 'write', method: :patch, path: 'jabvox/currencies/:id',
                           params: { id: :integer, symbol_jabvox: :string, name_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_item_type' => { permission: 'create', method: :post, path: 'jabvox/item_types',
                            params: { name_jabvox: :string, active_jabvox: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_item_type' => { permission: 'write', method: :patch, path: 'jabvox/item_types/:id',
                            params: { id: :integer, name_jabvox: :string, active_jabvox: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_unit_of_measure' => { permission: 'create', method: :post, path: 'jabvox/units_of_measure',
                                  params: { name_jabvox: :string, abbreviation_jabvox: :string, active_jabvox: :boolean },
                                  mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_unit_of_measure' => { permission: 'write', method: :patch, path: 'jabvox/units_of_measure/:id',
                                  params: { id: :integer, name_jabvox: :string, abbreviation_jabvox: :string, active_jabvox: :boolean },
                                  mcp: 'jabvox_core', feature: 'jabvox_products' },
    'create_tax_rate' => { permission: 'create', method: :post, path: 'jabvox/tax_rates',
                           params: { name_jabvox: :string, percentage_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },
    'update_tax_rate' => { permission: 'write', method: :patch, path: 'jabvox/tax_rates/:id',
                           params: { id: :integer, name_jabvox: :string, percentage_jabvox: :string, active_jabvox: :boolean },
                           mcp: 'jabvox_core', feature: 'jabvox_products' },

    # --- Leads (jabvox_leads) ---
    'bulk_assign_leads' => { permission: 'write', method: :post, path: 'jabvox/leads/bulk_assign',
                             params: { lead_ids: :json, assignee_id: :integer }, mcp: 'jabvox_leads', feature: 'jabvox_leads' },
    'bulk_unassign_leads' => { permission: 'write', method: :post, path: 'jabvox/leads/bulk_unassign',
                               params: { lead_ids: :json }, mcp: 'jabvox_leads', feature: 'jabvox_leads' },
    'update_lead_details' => { permission: 'write', method: :patch, path: 'jabvox/leads/:id/details',
                               params: { id: :integer, contact: :json, campaign_name: :string, assignee_id: :integer, custom_fields: :json },
                               mcp: 'jabvox_leads', feature: 'jabvox_leads' },
    'update_lead_custom_fields' => { permission: 'write', method: :patch, path: 'jabvox/leads/:id/custom_fields',
                                     params: { id: :integer, custom_fields: :json }, mcp: 'jabvox_leads', feature: 'jabvox_leads' },
    'claim_lead' => { permission: 'write', method: :post, path: 'jabvox/leads/:id/claim',
                      params: { id: :integer }, mcp: 'jabvox_leads', feature: 'jabvox_leads' },
    'sync_lead_contacts' => { permission: 'write', method: :post, path: 'jabvox/leads/sync_contacts',
                              mcp: 'jabvox_leads', feature: 'jabvox_leads' },

    # --- Afiliados (jabvox_affiliates) ---
    'create_affiliate' => { permission: 'create', method: :post, path: 'jabvox/affiliates',
                            params: { name: :string, active: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_affiliates' },
    'update_affiliate' => { permission: 'write', method: :patch, path: 'jabvox/affiliates/:id',
                            params: { id: :integer, name: :string, active: :boolean }, mcp: 'jabvox_core', feature: 'jabvox_affiliates' },
    'regenerate_affiliate_token' => { permission: 'write', method: :post, path: 'jabvox/affiliates/:id/regenerate_token',
                                      params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_affiliates' },
    'regenerate_affiliate_code' => { permission: 'write', method: :post, path: 'jabvox/affiliates/:id/regenerate_code',
                                     params: { id: :integer }, mcp: 'jabvox_core', feature: 'jabvox_affiliates' }
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
    jabvox_email jabvox_forms jabvox_internal_chat jabvox_kanban jabvox_lead_delete
    jabvox_lead_import jabvox_leads jabvox_products jabvox_response_bot jabvox_saldo jabvox_sms
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
    'get_bulk_whatsapp_batches' => 'Lista los lotes de envío masivo de WhatsApp.',
    'reuse_bulk_whatsapp_batch' => 'Reutiliza (reenvía) un lote de envío masivo de WhatsApp previo.'
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
        parameters: { type: 'object', properties: props, required: (spec[:params] || {}).keys.map(&:to_s) }
      }
    }
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
