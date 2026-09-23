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

  def initialize(account:, user:, hermes_name: nil)
    @account = account
    @user = user
    # Nombre visible del agente Hermes (para atribuir mensajes/notas a "Hermes", no al
    # usuario técnico ligado). Puede venir nil si no se propaga.
    @hermes_name = hermes_name.presence || 'Hermes'
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
    'GET automation_rules/:id' => :get_automation_rule,
    'PATCH automation_rules/:id/toggle' => :toggle_automation_rule,
    'POST automation_rules/:id/clone' => :clone_automation_rule,
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
    'GET jabvox/reports/products' => :report_products,
    'GET jabvox/reports/dialer' => :report_dialer,
    'GET jabvox/reports/agent_status' => :report_agent_status,
    'GET jabvox/reports/hermes_activity' => :report_hermes_activity,

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
    'GET jabvox/analytics/dashboards/:id' => :get_analytics_dashboard,
    'POST jabvox/analytics/dashboards' => :create_analytics_dashboard,
    'PATCH jabvox/analytics/dashboards/:id' => :update_analytics_dashboard,
    # normalize() colapsa cada /\d+ a /:id, por eso dashboards/:id/widgets → …/:id/widgets.
    'POST jabvox/analytics/dashboards/:id/widgets' => :create_analytics_widget,
    'PATCH jabvox/analytics/dashboards/:id/widgets/:id' => :update_analytics_widget,
    'POST jabvox/analytics/dashboards/:id/widgets/:id/execute' => :execute_analytics_widget,
    # Rutas literales (overview_stats/internal_reports no colapsan porque no son dígitos).
    'GET jabvox/analytics/dashboards/overview_stats' => :analytics_overview_stats,
    'GET jabvox/analytics/dashboards/internal_reports' => :analytics_internal_reports,
    'GET jabvox/analytics/folders' => :list_analytics_folders,
    'POST jabvox/analytics/folders' => :create_analytics_folder,
    'PATCH jabvox/analytics/folders/:id' => :update_analytics_folder,
    'GET jabvox/analytics/cross_reports' => :list_analytics_cross_reports,
    'GET jabvox/analytics/cross_reports/:id' => :get_analytics_cross_report,
    'POST jabvox/analytics/cross_reports/:id/execute' => :execute_analytics_cross_report,

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
    'GET jabvox/flows/:id' => :get_flow,
    'POST jabvox/flows' => :create_flow,
    'PATCH jabvox/flows/:id' => :update_flow,
    'PATCH jabvox/flows/:id/status' => :set_flow_status,
    'POST jabvox/flows/:id/duplicate' => :duplicate_flow,
    'GET jabvox/flows/:id/validate' => :validate_flow,
    'GET jabvox/flows/node_types' => :get_flow_node_types,
    'POST jabvox/flows/:id/save_version' => :save_flow_graph,
    'POST jabvox/flows/:id/run_node' => :test_flow_node,
    'POST jabvox/flows/:id/run' => :run_flow,
    'GET jabvox/bulk_whatsapp/batches' => :list_bulk_whatsapp_batches,
    'GET jabvox/bulk_whatsapp/batches/:id' => :get_bulk_whatsapp_batch,
    'POST jabvox/bulk_whatsapp/batches' => :create_bulk_whatsapp_batch,
    'POST jabvox/bulk_whatsapp/batches/:id/reuse' => :reuse_bulk_whatsapp_batch,
    # Grupos de WhatsApp
    'GET jabvox/whatsapp_groups/groups' => :list_whatsapp_groups,
    'GET jabvox/whatsapp_groups/groups/:id' => :get_whatsapp_group,
    'POST jabvox/whatsapp_groups/groups' => :create_whatsapp_group,
    'PATCH jabvox/whatsapp_groups/groups/:id' => :update_whatsapp_group,
    'POST jabvox/whatsapp_groups/groups/:id/members' => :add_whatsapp_group_member,
    'POST jabvox/whatsapp_groups/groups/:id/messages' => :send_whatsapp_group_message,
    # Voice Broadcast (gestión de campañas; el backend hace la marcación, sin AMI aquí)
    'GET jabvox/voice_broadcasts' => :list_voice_broadcasts,
    'GET jabvox/voice_broadcasts/:id' => :get_voice_broadcast,
    'GET jabvox/voice_broadcasts/:id/report' => :get_voice_broadcast_report,
    'POST jabvox/voice_broadcasts' => :create_voice_broadcast,
    'PATCH jabvox/voice_broadcasts/:id' => :update_voice_broadcast,
    'POST jabvox/voice_broadcasts/:id/start' => :start_voice_broadcast,
    'POST jabvox/voice_broadcasts/:id/pause' => :pause_voice_broadcast,
    'POST jabvox/voice_broadcasts/:id/resume' => :resume_voice_broadcast,
    'POST jabvox/voice_broadcasts/:id/stop' => :stop_voice_broadcast,
    'GET jabvox/whatsapp_templates/templates' => :list_whatsapp_templates,
    'POST jabvox/whatsapp_templates/templates' => :create_whatsapp_template,
    'PATCH jabvox/whatsapp_templates/templates/:id' => :update_whatsapp_template,
    'POST jabvox/whatsapp_templates/templates/:id/duplicate' => :duplicate_whatsapp_template,
    'POST jabvox/whatsapp_templates/templates/:id/sync' => :sync_whatsapp_template,
    'POST jabvox/whatsapp_templates/templates/:id/send_to_contact' => :send_whatsapp_template_to_contact,
    'GET jabvox/affiliates' => :list_affiliates,
    'GET jabvox/campaigns' => :list_campaigns,
    'GET jabvox/cdr/records' => :list_cdr_records,
    'GET jabvox/custom_tables' => :list_custom_tables,

    # ===== LOTE "TODO ES TODO" =====
    # Comunicación
    'POST inboxes' => :create_api_inbox,
    'POST conversations/:id/toggle_status' => :update_conversation_status,
    'POST conversations/:id/assignments' => :assign_conversation,
    # Email templates
    'GET jabvox/email_templates' => :list_email_templates,
    'POST jabvox/email_templates' => :create_email_template,
    'PATCH jabvox/email_templates/:id' => :update_email_template,
    'POST jabvox/email_templates/:id/test_send' => :test_send_email_template,
    'POST jabvox/email_templates/:id/send_to_contact' => :send_email_template_to_contact,
    # Forms
    'GET jabvox/forms' => :list_forms,
    'GET jabvox/forms/:id' => :get_form,
    'POST jabvox/forms' => :create_form,
    'PATCH jabvox/forms/:id' => :update_form,
    # Tareas
    'POST jabvox/tasks' => :create_task,
    'PATCH jabvox/tasks/:id' => :update_task,
    'PATCH jabvox/tasks/:id/move' => :move_task,
    'POST jabvox/task_boards' => :create_task_board,
    'PATCH jabvox/task_boards/:id' => :update_task_board,
    'POST jabvox/task_stages' => :create_task_stage,
    'PATCH jabvox/task_stages/:id' => :update_task_stage,
    'POST jabvox/task_lead_contacts' => :create_task_lead_contact,
    'PATCH jabvox/task_lead_contacts/:id' => :update_task_lead_contact,
    # Calendario
    'POST jabvox/calendar/events' => :create_calendar_event,
    'PATCH jabvox/calendar/events/:id' => :update_calendar_event,
    'POST jabvox/calendar/external_people' => :create_calendar_external_person,
    'PATCH jabvox/calendar/external_people/:id' => :update_calendar_external_person,
    # Chat interno
    'GET jabvox/internal_chats' => :list_internal_chats,
    'POST jabvox/internal_chats' => :create_internal_chat,
    'POST jabvox/internal_chats/:id/send_message' => :send_internal_chat_message,
    'POST jabvox/internal_chats/:id/mark_read' => :mark_internal_chat_read,
    # Kanban
    'POST jabvox/kanban_funnels' => :create_kanban_funnel,
    'PATCH jabvox/kanban_funnels/:id' => :update_kanban_funnel,
    'POST jabvox/kanban_stages' => :create_kanban_stage,
    'PATCH jabvox/kanban_stages/:id' => :update_kanban_stage,
    # Gestiones
    'GET jabvox/management_states/export' => :export_management_states,
    # Dialer
    'PATCH jabvox/dialer_campaigns/:id/start' => :start_dialer_campaign,
    'PATCH jabvox/dialer_campaigns/:id/pause' => :pause_dialer_campaign,
    'PATCH jabvox/dialer_campaigns/:id/stop' => :stop_dialer_campaign,
    'PATCH jabvox/dialer_campaigns/:id/retry_contacts' => :retry_dialer_campaign,
    'PATCH jabvox/dialer_campaigns/:id/redial_lead' => :redial_dialer_lead,
    'PATCH jabvox/dialer_campaigns/:id/exclude_lead' => :exclude_dialer_lead,
    'POST jabvox/dialer_campaigns/:id/import_contacts' => :import_dialer_contacts,
    'GET jabvox/dialer_campaigns/:id/progress' => :dialer_campaign_progress,
    'GET jabvox/dialer_states' => :list_dialer_states,
    'POST jabvox/dialer_states' => :create_dialer_state,
    'PATCH jabvox/dialer_states/:id' => :update_dialer_state,
    'GET jabvox/dialer_call_logs' => :list_dialer_call_logs,
    'PATCH jabvox/dialer_call_logs/typify' => :typify_dialer_call,
    # Click-to-call
    'GET jabvox/click_to_call/call_logs' => :list_click_to_call_logs,
    'PATCH jabvox/click_to_call/call_logs/:id' => :typify_click_to_call,
    # CDR
    'POST jabvox/cdr/sync_now' => :sync_cdr_now,
    'POST jabvox/cdr/analyze' => :analyze_cdr_call,
    'POST jabvox/cdr/typify' => :typify_cdr_call,
    # Tickets
    'POST jabvox/tickets/tickets' => :create_ticket,
    'PATCH jabvox/tickets/tickets/:id' => :update_ticket,
    'POST jabvox/tickets/tickets/:id/assign' => :assign_ticket,
    'POST jabvox/tickets/tickets/:id/change_status' => :change_ticket_status,
    'POST jabvox/tickets/tickets/:id/resolve' => :resolve_ticket,
    'POST jabvox/tickets/tickets/:id/reopen' => :reopen_ticket,
    'POST jabvox/tickets/tickets/:id/rate' => :rate_ticket,
    'POST jabvox/tickets/tickets/:id/merge' => :merge_ticket,
    'GET jabvox/tickets/tickets/:id/comments' => :list_ticket_comments,
    'POST jabvox/tickets/tickets/:id/comments' => :create_ticket_comment,
    # Datos personalizados
    'POST jabvox/custom_tables' => :create_custom_table,
    'PATCH jabvox/custom_tables/:id' => :update_custom_table,
    'POST jabvox/custom_tables/:id/custom_columns' => :create_custom_column,
    'PATCH jabvox/custom_tables/:id/custom_columns/:id' => :update_custom_column,
    'POST jabvox/custom_tables/:id/data' => :create_custom_table_row,
    'PATCH jabvox/custom_tables/:id/data/:id' => :update_custom_table_row,
    'POST jabvox/quick_buttons' => :create_quick_button,
    'PATCH jabvox/quick_buttons/:id' => :update_quick_button,
    # Productos
    'POST jabvox/products' => :create_product,
    'PATCH jabvox/products/:id' => :update_product,
    'POST jabvox/orders' => :create_order,
    'PATCH jabvox/orders/:id' => :update_order,
    'POST jabvox/orders/:id/send_to_alegra' => :send_order_to_alegra,
    'POST jabvox/discounts' => :create_discount,
    'PATCH jabvox/discounts/:id' => :update_discount,
    'POST jabvox/order_status_configs' => :create_order_status_config,
    'PATCH jabvox/order_status_configs/:id' => :update_order_status_config,
    'POST jabvox/currencies' => :create_currency,
    'PATCH jabvox/currencies/:id' => :update_currency,
    'POST jabvox/item_types' => :create_item_type,
    'PATCH jabvox/item_types/:id' => :update_item_type,
    'POST jabvox/units_of_measure' => :create_unit_of_measure,
    'PATCH jabvox/units_of_measure/:id' => :update_unit_of_measure,
    'POST jabvox/tax_rates' => :create_tax_rate,
    'PATCH jabvox/tax_rates/:id' => :update_tax_rate,
    # Leads
    'POST jabvox/leads/bulk_assign' => :bulk_assign_leads,
    'POST jabvox/leads/bulk_unassign' => :bulk_unassign_leads,
    'PATCH jabvox/leads/:id/details' => :update_lead_details,
    'PATCH jabvox/leads/:id/custom_fields' => :update_lead_custom_fields,
    'POST jabvox/leads/:id/claim' => :claim_lead,
    'POST jabvox/leads/sync_contacts' => :sync_lead_contacts,
    # Afiliados
    'POST jabvox/affiliates' => :create_affiliate,
    'PATCH jabvox/affiliates/:id' => :update_affiliate,
    'POST jabvox/affiliates/:id/regenerate_token' => :regenerate_affiliate_token,
    'POST jabvox/affiliates/:id/regenerate_code' => :regenerate_affiliate_code,
    # Saldo IA (LiteLLM)
    'GET jabvox/ai_balance' => :get_ai_balance,
    'GET jabvox/ai_balance/movements' => :get_ai_balance_movements,
    'POST jabvox/ai_balance/refresh' => :refresh_ai_balance,
    'GET jabvox/saldo_configs' => :list_saldo_configs,
    # Lista blanca de IP
    'GET jabvox/ip_whitelists' => :list_ip_whitelists,
    'POST jabvox/ip_whitelists' => :create_ip_whitelist,
    'PATCH jabvox/ip_whitelists/:id' => :update_ip_whitelist,
    # Horarios de atención
    'GET jabvox/working_hours' => :get_working_hours,
    'PATCH jabvox/working_hours' => :update_working_hour,
    # Macros
    'GET macros' => :list_macros,
    'GET macros/:id' => :get_macro,
    'POST macros' => :create_macro,
    'PATCH macros/:id' => :update_macro,
    # Equipos y agentes
    'GET teams' => :list_teams,
    'GET teams/:id' => :get_team,
    'POST teams' => :create_team,
    'PATCH teams/:id' => :update_team,
    'GET agents' => :list_agents,
    # Etiquetas de conversación
    'GET conversations/:id/labels' => :get_conversation_labels,
    'POST conversations/:id/labels' => :add_conversation_label,
    'PATCH conversations/:id/labels/remove' => :remove_conversation_label,
    # Kanban: tablero, tarjetas y automatizaciones de columna
    'GET jabvox/kanban_stages' => :list_kanban_stages,
    'GET jabvox/kanban_board' => :get_kanban_board,
    'GET jabvox/kanban_stages/:stage_id/cards' => :get_kanban_stage_cards,
    'PATCH jabvox/kanban_cards/move' => :move_kanban_card,
    'GET jabvox/kanban_stage_automations' => :list_kanban_stage_automations,
    'POST jabvox/kanban_stage_automations' => :create_kanban_stage_automation,
    'PATCH jabvox/kanban_stage_automations/:id' => :update_kanban_stage_automation,
    # Calendario: personas externas (listado)
    'GET jabvox/calendar/external_people' => :list_calendar_external_people,
    # Catálogos y configuración
    'GET jabvox/typifications' => :list_typifications,
    'POST jabvox/typifications' => :create_typification,
    'PATCH jabvox/typifications/:id' => :update_typification,
    'GET jabvox/currencies' => :list_currencies,
    'POST jabvox/currencies' => :create_currency,
    'PATCH jabvox/currencies/:id' => :update_currency,
    'GET jabvox/units_of_measure' => :list_units_of_measure,
    'POST jabvox/units_of_measure' => :create_unit_of_measure,
    'PATCH jabvox/units_of_measure/:id' => :update_unit_of_measure,
    'GET jabvox/field_visibilities' => :list_field_visibilities,
    'PATCH jabvox/field_visibilities' => :update_field_visibility,
    'GET jabvox/user_extensions' => :list_user_extensions,
    'PATCH jabvox/user_extensions' => :update_user_extension,
    'GET jabvox/smtp_config' => :get_smtp_config,
    'GET jabvox/voip_config' => :get_voip_config,
    'GET jabvox/sms_providers' => :list_sms_providers,
    'GET jabvox/sms_messages' => :list_sms_messages
  }.freeze

  # Los handlers de dominio viven en ServiceHandlers (para mantener el dispatch pequeño).
  include Jabvox::Hermes::ListFilters
  include Jabvox::Hermes::ServiceHandlers
  include Jabvox::Hermes::ServiceHandlersPlatform
  include Jabvox::Hermes::ServiceHandlersKanban
  include Jabvox::Hermes::ServiceHandlersConfig
end
