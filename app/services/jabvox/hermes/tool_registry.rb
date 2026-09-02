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

    # --- Envíos masivos WhatsApp (módulo jabvox_bulk_whatsapp) ---
    'get_bulk_whatsapp_batches' => { permission: 'read', method: :get, path: 'jabvox/bulk_whatsapp/batches',
                                     mcp: 'jabvox_core', feature: 'jabvox_bulk_whatsapp' },

    # --- Plantillas WhatsApp (módulo jabvox_whatsapp_templates) ---
    'get_whatsapp_templates' => { permission: 'read', method: :get, path: 'jabvox/whatsapp_templates/templates',
                                  mcp: 'jabvox_core', feature: 'jabvox_whatsapp_templates' },

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
                             mcp: 'jabvox_core', feature: 'jabvox_customization' }
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
    'get_calendar_events' => 'Lista eventos del calendario (módulo Calendario).'
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
