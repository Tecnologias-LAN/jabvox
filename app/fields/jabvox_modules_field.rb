require 'administrate/field/base'

# Renders all the per-account Jabvox module toggles as one grouped field —
# tiles organized by CATEGORY (Bandejas y Canales, Telefonía y Voz, IA y
# Automatización, CRM y Gestión, Otros) instead of ~31 flat rows. Show page
# displays each module with an on/off indicator; form page renders a checkbox
# per module. The category grouping is the single source of truth for both views.
class JabvoxModulesField < Administrate::Field::Base
  # Business-facing categories, in display order. Each groups related modules so
  # the Super Admin scans by area (channels, telephony, AI…) instead of a long list.
  CATEGORIES = [
    { key: :channels, label: 'Bandejas y Canales', icon: '💬' },
    { key: :telephony, label: 'Telefonía y Voz', icon: '📞' },
    { key: :ai, label: 'IA y Automatización', icon: '🤖' },
    { key: :crm, label: 'CRM y Gestión', icon: '📇' },
    { key: :other, label: 'Otros', icon: '🧩' }
  ].freeze

  # Each module: [account boolean column, human label, category key].
  MODULES = [
    # Bandejas y Canales
    [:jabvox_voip_enabled_jabvox, 'VoIP', :channels],
    [:jabvox_softphone_enabled_jabvox, 'Softphone', :channels],
    [:jabvox_click_to_call_enabled_jabvox, 'Click to Call', :channels],
    [:jabvox_sms_enabled_jabvox, 'SMS', :channels],
    [:jabvox_email_enabled_jabvox, 'Email', :channels],
    [:jabvox_bulk_whatsapp_enabled_jabvox, 'WhatsApp Masivo', :channels],
    [:jabvox_whatsapp_groups_enabled_jabvox, 'WhatsApp Grupos', :channels],
    [:jabvox_whatsapp_templates_enabled_jabvox, 'WhatsApp Templates', :channels],
    # Telefonía y Voz
    [:jabvox_dialer_enabled_jabvox, 'Dialer', :telephony],
    [:jabvox_voice_broadcast_enabled_jabvox, 'Voice Broadcast', :telephony],
    [:jabvox_cdr_enabled_jabvox, 'CDR (Grabaciones)', :telephony],
    [:jabvox_audio_analysis_enabled_jabvox, 'Análisis de Audio', :telephony],
    [:jabvox_saldo_enabled_jabvox, 'Saldo', :telephony],
    # IA y Automatización
    [:jabvox_ai_chat_enabled_jabvox, 'AI Chat', :ai],
    [:jabvox_ai_chat_provisioning_enabled_jabvox, 'Chat Aprovisionamiento', :ai],
    [:jabvox_advanced_automations_enabled_jabvox, 'Automatizaciones Avanzadas', :ai],
    [:jabvox_analytics_enabled_jabvox, 'Analytics', :ai],
    # CRM y Gestión
    [:jabvox_leads_enabled_jabvox, 'Leads', :crm],
    [:jabvox_lead_import_enabled_jabvox, 'Importar Leads', :crm],
    [:jabvox_lead_delete_enabled_jabvox, 'Eliminar Leads', :crm],
    [:jabvox_kanban_enabled_jabvox, 'Kanban', :crm],
    [:jabvox_tasks_enabled_jabvox, 'Tareas', :crm],
    [:jabvox_tickets_enabled_jabvox, 'Tickets', :crm],
    [:jabvox_calendar_enabled_jabvox, 'Calendario', :crm],
    [:jabvox_affiliates_enabled_jabvox, 'Afiliados', :crm],
    [:jabvox_forms_enabled_jabvox, 'Formularios', :crm],
    # Otros
    [:jabvox_products_enabled_jabvox, 'Productos', :other],
    [:jabvox_internal_chat_enabled_jabvox, 'Chat Interno', :other],
    [:jabvox_customization_enabled_jabvox, 'Personalización', :other],
    [:jabvox_data_export_enabled_jabvox, 'Exportar Datos', :other]
  ].freeze

  # [[column, label, enabled_boolean], ...] for the current account.
  # Skips any module whose column is not present yet (e.g. a code deploy that ran
  # ahead of its migration) so the Super Admin never 500s over a missing column.
  def modules
    available = resource.class.column_names
    MODULES.filter_map do |column, label, category|
      next unless available.include?(column.to_s)

      [column, label, resource.public_send(column), category]
    end
  end

  # Modules grouped by category, in CATEGORIES order. Each entry:
  # { key:, label:, icon:, modules: [[column, label, enabled], ...] }.
  # Empty categories (all their columns missing) are dropped.
  def grouped_modules
    by_cat = modules.group_by { |_col, _label, _on, cat| cat }
    CATEGORIES.filter_map do |cat|
      rows = by_cat[cat[:key]]
      next if rows.blank?

      cat.merge(modules: rows.map { |col, label, on, _cat| [col, label, on] })
    end
  end

  def enabled_count
    modules.count { |_column, _label, on, _cat| on }
  end

  def total_count
    modules.size
  end
end
