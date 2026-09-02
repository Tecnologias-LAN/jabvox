# frozen_string_literal: true

# Capa de servicio interna: traduce una tool YA AUTORIZADA a una acción real sobre los
# modelos/servicios de dominio de Jabvox. Es la frontera que garantiza que Hermes NUNCA
# ejecuta SQL ni toca la BD directamente: todo pasa por ActiveRecord con el account SIEMPRE
# forzado a la cuenta del contexto (nunca uno enviado por el LLM), evitando cross-account.
#
# Cada acción se despacha por (method, path) a un handler explícito (whitelist). Un path no
# mapeado se rechaza — no hay ejecución genérica de HTTP ni de SQL.
class Jabvox::Hermes::ServiceLayer
  UnknownAction = Class.new(StandardError)

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  Forbidden = Class.new(StandardError)

  # Enruta a un handler concreto. `path` ya viene con placeholders resueltos.
  def call(method:, path:, params:)
    verb = method.to_s.upcase
    # POLÍTICA: borrar está prohibido a nivel de motor, no solo por falta de ruta.
    raise Forbidden, 'borrar registros de Jabvox no está permitido' if verb == 'DELETE'

    key = "#{verb} #{normalize(path)}"
    handler = ROUTES[key]
    raise UnknownAction, "acción no soportada: #{key}" unless handler

    send(handler, params)
  end

  private

  # Normaliza un path concreto a su plantilla (labels/5 → labels/:id) para el ruteo.
  def normalize(path)
    path.gsub(%r{/\d+}, '/:id')
  end

  # Límite de filas por lectura (evita respuestas enormes al LLM).
  MAX_ROWS = 50

  # Whitelist de rutas → handler. Coincide con ToolRegistry. Solo GET/POST/PATCH: no hay
  # ninguna ruta DELETE — borrar está prohibido por política. TODO scoped a @account.
  ROUTES = {
    # Etiquetas
    'GET labels' => :list_labels,
    'POST labels' => :create_label,
    'PATCH labels/:id' => :update_label,
    # Bandejas
    'GET inboxes' => :list_inboxes,
    # Contactos
    'GET contacts/search' => :search_contacts,
    'GET contacts/:id' => :get_contact,
    'POST contacts' => :create_contact,
    'PATCH contacts/:id' => :update_contact,
    # Conversaciones + mensajes + notas privadas
    'GET conversations/meta' => :conversations_meta,
    'GET conversations' => :list_conversations,
    'GET conversations/:id/messages' => :list_conversation_messages,
    'GET conversations/:id/summary' => :summarize_conversation,
    'POST conversations/:id/messages' => :reply_conversation,
    'POST conversations/:id/notes' => :add_private_note,
    # Notas de contacto
    'GET contacts/:id/notes' => :list_contact_notes,
    'POST contacts/:id/notes' => :create_contact_note,
    # Automatizaciones
    'GET automation_rules' => :list_automation_rules,
    'POST automation_rules' => :create_automation_rule,
    'PATCH automation_rules/:id' => :update_automation_rule,
    # Integración por webhook directo al Hermes (así responde bandejas)
    'GET webhooks' => :list_webhooks,
    'POST webhooks' => :create_hermes_webhook,
    'POST webhooks/inbox' => :create_hermes_inbox_webhook,
    # Leads
    'GET jabvox/leads' => :search_leads,
    'GET jabvox/leads/:id' => :get_lead,
    # Gestiones
    'GET jabvox/management_states' => :list_management_states,
    'POST jabvox/management_states' => :create_management_state,
    'PATCH jabvox/management_states/:id' => :update_management_state,
    # Dialer
    'GET jabvox/dialer_campaigns' => :list_dialer_campaigns,
    'GET jabvox/dialer_campaigns/:id' => :get_dialer_campaign,
    'POST jabvox/dialer_campaigns' => :create_dialer_campaign,
    'PATCH jabvox/dialer_campaigns/:id' => :update_dialer_campaign,
    # Masivos
    'GET jabvox/sms_campaigns' => :list_sms_campaigns,
    'POST jabvox/sms_campaigns' => :create_sms_campaign,
    'PATCH jabvox/sms_campaigns/:id' => :update_sms_campaign,
    # Reportes (solo lectura)
    'GET jabvox/reports/agents' => :report_agents_summary,

    # Análisis de Audio
    'GET jabvox/audio/jobs' => :list_audio_jobs,
    'GET jabvox/audio/jobs/:id' => :get_audio_job,
    'GET jabvox/audio/pipelines' => :list_audio_pipelines,

    # Analytics / BD externas
    'GET jabvox/analytics/data_sources' => :list_analytics_data_sources,
    'GET jabvox/analytics/data_sources/:id' => :get_analytics_data_source,
    'GET jabvox/analytics/data_sources/:id/schema' => :analytics_data_source_schema,
    'POST jabvox/analytics/data_sources/:id/custom_sql' => :run_analytics_query,
    'GET jabvox/analytics/data_sources/:id/preview' => :preview_analytics_table,
    'GET jabvox/analytics/dashboards' => :list_analytics_dashboards,

    # Importar leads
    'GET jabvox/lead_import/sources' => :list_lead_import_sources,
    'GET jabvox/lead_import/sources/:id' => :get_lead_import_source,
    'POST jabvox/lead_import/sources/:id/sync' => :trigger_lead_import_sync,
    'GET jabvox/lead_import/sources/:id/sync_status' => :lead_import_sync_status,

    # Exportar datos
    'GET jabvox/data_export/targets' => :list_data_export_targets,
    'GET jabvox/data_export/targets/:id' => :get_data_export_target,
    'POST jabvox/data_export/targets/:id/sync_now' => :trigger_data_export_sync,

    # Pedidos / productos
    'GET jabvox/orders' => :list_orders,
    'GET jabvox/orders/:id' => :get_order,
    'GET jabvox/products' => :list_products,
    'GET jabvox/products/:id' => :get_product,

    # Tareas / calendario / tickets / kanban / flows / otros
    'GET jabvox/tasks' => :list_tasks,
    'GET jabvox/tasks/boards' => :list_task_boards,
    'GET jabvox/calendar/events' => :list_calendar_events,
    'GET jabvox/tickets' => :list_tickets,
    'GET jabvox/tickets/:id' => :get_ticket,
    'GET jabvox/kanban_funnels' => :list_kanban_funnels,
    'GET jabvox/flows' => :list_flows,
    'POST jabvox/flows/:id/run' => :run_flow,
    'GET jabvox/bulk_whatsapp/batches' => :list_bulk_whatsapp_batches,
    'GET jabvox/whatsapp_templates/templates' => :list_whatsapp_templates,
    'GET jabvox/affiliates' => :list_affiliates,
    'GET jabvox/campaigns' => :list_campaigns,
    'GET jabvox/cdr/records' => :list_cdr_records,
    'GET jabvox/custom_tables' => :list_custom_tables
  }.freeze

  # Los handlers de dominio viven en ServiceHandlers (para mantener el dispatch pequeño).
  include Jabvox::Hermes::ServiceHandlers
end
