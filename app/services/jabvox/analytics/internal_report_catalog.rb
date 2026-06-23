# Catalog of built-in (internal) analytics reports. These run as plain Ruby
# services scoped to a single account — there is NO raw SQL and the account_id
# is applied through ActiveRecord associations, so a report can never read
# another account's data.
#
# Each entry maps a stable `key` (stored on the widget config) to the service
# class that produces the report. The widget executor looks the class up here;
# unknown keys are rejected.
class Jabvox::Analytics::InternalReportCatalog
  REPORTS = [
    { key: 'sales',          label: 'Ventas',          icon: 'i-lucide-shopping-cart',  service: 'SalesReportService' },
    { key: 'calls',          label: 'Llamadas',        icon: 'i-lucide-phone',          service: 'CallsReportService' },
    { key: 'agents',         label: 'Agentes',         icon: 'i-lucide-users',          service: 'AgentsReportService' },
    { key: 'whatsapp',       label: 'WhatsApp',        icon: 'i-lucide-message-circle', service: 'WhatsappReportService' },
    { key: 'email',          label: 'Email',           icon: 'i-lucide-mail',           service: 'EmailReportService' },
    { key: 'sms',            label: 'SMS',             icon: 'i-lucide-message-square', service: 'SmsReportService' },
    { key: 'chat_internal',  label: 'Chat Interno',    icon: 'i-lucide-messages-square', service: 'ChatInternalReportService' },
    { key: 'chat_ai',        label: 'Chat IA',         icon: 'i-lucide-bot',            service: 'ChatAiReportService' },
    { key: 'cdr_analysis',   label: 'Análisis CDR',    icon: 'i-lucide-phone-call',     service: 'CdrAnalysisReportService' },
    { key: 'audio_analysis', label: 'Análisis Audio',  icon: 'i-lucide-audio-lines',    service: 'AudioAnalysisReportService' },
    # Built-in Chatwoot reports (the /reports pages), account-scoped.
    { key: 'overview',       label: 'Resumen',         icon: 'i-lucide-layout-dashboard', service: 'OverviewReportService' },
    { key: 'conversations',  label: 'Conversaciones',  icon: 'i-lucide-messages-square', service: 'ConversationsReportService' },
    { key: 'csat',           label: 'CSAT',            icon: 'i-lucide-smile',          service: 'CsatReportService' },
    { key: 'report_agents',  label: 'Agentes (Informes)',  icon: 'i-lucide-user-round', service: 'ReportAgentsReportService' },
    { key: 'report_inboxes', label: 'Bandejas (Informes)', icon: 'i-lucide-inbox',      service: 'ReportInboxesReportService' },
    { key: 'report_labels',  label: 'Etiquetas (Informes)', icon: 'i-lucide-tags',      service: 'ReportLabelsReportService' }
  ].freeze

  KEYS = REPORTS.pluck(:key).freeze

  def self.all
    REPORTS.map { |r| r.slice(:key, :label, :icon) }
  end

  def self.exists?(key)
    KEYS.include?(key.to_s)
  end

  # Resolve a report key to its service class, or nil if the key is unknown
  # or the service has not been implemented yet.
  def self.service_for(key)
    entry = REPORTS.find { |r| r[:key] == key.to_s }
    return nil unless entry

    "Jabvox::Analytics::Reports::#{entry[:service]}".safe_constantize
  end
end
