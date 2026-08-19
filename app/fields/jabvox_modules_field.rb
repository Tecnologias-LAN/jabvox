require 'administrate/field/base'

# Renders all the per-account Jabvox module toggles as one grouped field —
# a grid of tiles (like the "All features" block) instead of ~25 separate
# boolean rows. Show page displays each module with an on/off indicator;
# form page renders a checkbox per module.
class JabvoxModulesField < Administrate::Field::Base
  # Each module: the boolean account column and its human label.
  MODULES = [
    [:jabvox_kanban_enabled_jabvox, 'Jabvox Kanban'],
    [:jabvox_products_enabled_jabvox, 'Jabvox Productos'],
    [:jabvox_voip_enabled_jabvox, 'Jabvox VoIP'],
    [:jabvox_saldo_enabled_jabvox, 'Jabvox Saldo'],
    [:jabvox_sms_enabled_jabvox, 'Jabvox SMS'],
    [:jabvox_ai_chat_enabled_jabvox, 'Jabvox AI Chat'],
    [:jabvox_dialer_enabled_jabvox, 'Jabvox Dialer'],
    [:jabvox_leads_enabled_jabvox, 'Jabvox Leads'],
    [:jabvox_affiliates_enabled_jabvox, 'Jabvox Afiliados'],
    [:jabvox_calendar_enabled_jabvox, 'Jabvox Calendario'],
    [:jabvox_internal_chat_enabled_jabvox, 'Jabvox Chat Interno'],
    [:jabvox_response_bot_enabled_jabvox, 'Jabvox Response Bot'],
    [:jabvox_email_enabled_jabvox, 'Jabvox Email'],
    [:jabvox_forms_enabled_jabvox, 'Jabvox Formularios'],
    [:jabvox_cdr_enabled_jabvox, 'Jabvox CDR'],
    [:jabvox_audio_analysis_enabled_jabvox, 'Jabvox Análisis de Audio'],
    [:jabvox_click_to_call_enabled_jabvox, 'Jabvox Click to Call'],
    [:jabvox_customization_enabled_jabvox, 'Jabvox Personalización'],
    [:jabvox_analytics_enabled_jabvox, 'Jabvox Analytics'],
    [:jabvox_whatsapp_templates_enabled_jabvox, 'Jabvox WhatsApp Templates'],
    [:jabvox_tasks_enabled_jabvox, 'Jabvox Tareas'],
    [:jabvox_tickets_enabled_jabvox, 'Jabvox Tickets'],
    [:jabvox_bulk_whatsapp_enabled_jabvox, 'Jabvox WhatsApp Masivo'],
    [:jabvox_whatsapp_groups_enabled_jabvox, 'Jabvox WhatsApp Grupos'],
    [:jabvox_voice_broadcast_enabled_jabvox, 'Jabvox Voice Broadcast'],
    [:jabvox_lead_import_enabled_jabvox, 'Jabvox Importar Leads'],
    [:jabvox_data_export_enabled_jabvox, 'Jabvox Exportar Datos'],
    [:jabvox_lead_delete_enabled_jabvox, 'Jabvox Eliminar Leads'],
    [:jabvox_advanced_automations_enabled_jabvox, 'Automatizaciones Avanzadas'],
    [:jabvox_softphone_enabled_jabvox, 'Jabvox Softphone'],
    [:jabvox_ai_chat_provisioning_enabled_jabvox, 'Jabvox Chat Aprovisionamiento']
  ].freeze

  # [[column, label, enabled_boolean], ...] for the current account.
  # Skips any module whose column is not present yet (e.g. a code deploy that ran
  # ahead of its migration) so the Super Admin never 500s over a missing column.
  def modules
    available = resource.class.column_names
    MODULES.filter_map do |column, label|
      next unless available.include?(column.to_s)

      [column, label, resource.public_send(column)]
    end
  end

  def enabled_count
    modules.count { |_column, _label, on| on }
  end
end
