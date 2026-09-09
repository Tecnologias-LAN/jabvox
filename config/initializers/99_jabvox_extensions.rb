Rails.application.config.to_prepare do
  Conversation.include Jabvox::KanbanConversationHooks
  # Assigning a conversation also assigns (and creates, if missing) the contact's lead.
  Conversation.include Jabvox::ConversationLeadAssignment
  Account.prepend Jabvox::AccountKanbanFeature
  Account.prepend Jabvox::AccountProductsFeature
  Account.prepend Jabvox::AccountVoipFeature
  Account.prepend Jabvox::AccountSaldoFeature
  Account.prepend Jabvox::AccountSmsFeature
  Account.prepend Jabvox::AccountAiChatFeature
  Account.prepend Jabvox::AccountDialerFeature
  Account.prepend Jabvox::AccountLeadsFeature
  Account.prepend Jabvox::AccountAffiliatesFeature
  Account.prepend Jabvox::AccountCalendarFeature
  Account.prepend Jabvox::AccountInternalChatFeature
  Account.prepend Jabvox::AccountEmailFeature
  Account.prepend Jabvox::AccountFormsFeature
  Account.prepend Jabvox::AccountCdrFeature
  Account.prepend Jabvox::AccountVoiceBroadcastFeature
  Account.prepend Jabvox::AccountAudioAnalysisFeature
  Account.prepend Jabvox::AccountClickToCallFeature
  Account.prepend Jabvox::AccountCustomizationFeature
  Account.prepend Jabvox::AccountAnalyticsFeature
  Account.prepend Jabvox::AccountWhatsappTemplatesFeature
  Account.prepend Jabvox::AccountTasksFeature
  Account.prepend Jabvox::AccountBulkWhatsappFeature
  Account.prepend Jabvox::AccountWhatsappGroupsFeature
  Account.prepend Jabvox::AccountTicketsFeature
  # Notification soporta tickets como primary_actor sin romper el flujo de conversación.
  Notification.prepend Jabvox::TicketNotificationSupport
  Account.prepend Jabvox::AccountLeadImportFeature
  Account.prepend Jabvox::AccountDataExportFeature
  Account.prepend Jabvox::AccountLeadDeleteFeature
  Account.prepend Jabvox::AccountAdvancedAutomationsFeature
  Account.prepend Jabvox::AccountSoftphoneFeature
  Account.prepend Jabvox::AccountAiChatProvisioningFeature
  # Prevents a PostgreSQL bigint overflow in feature_flags when a default
  # feature sits at bit >= 64 (upstream Chatwoot has > 63 features). Keeps
  # account creation from 500-ing regardless of the DB feature-defaults config.
  Account.prepend Jabvox::AccountFeatureFlagGuard
  # Virtual `jabvox_modules` reader for the Super Admin grouped module tiles.
  Account.include Jabvox::AccountModulesAdmin
  # Backfill CDR <-> Audio pipelines when both modules become enabled.
  Account.include Jabvox::AccountPipelineSync
  # Backfill Audio <-> AI Chat storages when both modules become enabled.
  Account.include Jabvox::AccountStorageSync

  Contact.include Jabvox::ContactLeadsIntegration
  Note.include Jabvox::NoteManagementAnswers
  # Records label apply/remove intervals per conversation for the WhatsApp report.
  Conversation.include Jabvox::ConversationLabelLogging
  Api::V1::Accounts::ContactsController.include Jabvox::ContactFieldProtection

  # Route WhatsApp Groups API webhook events (group_* fields) into the Jabvox
  # handler; non-group payloads fall through to the existing chain.
  Webhooks::WhatsappEventsJob.prepend Jabvox::WhatsappGroupEventsJob
end

# Real-time export: mirror every exportable jabvox model to the account's external
# DB. This must run AFTER the app is fully initialized (all models eager-loaded),
# so the catalog's ObjectSpace scan sees every model regardless of load order.
# Runs once at boot; in production models are already eager-loaded, in development
# the catalog forces an eager_load! before scanning.
Rails.application.config.after_initialize do
  # Skip when the DB isn't migrated yet (e.g. db:schema:load / db:migrate on a
  # fresh database): the export catalog eager-loads models, and some (Administrate
  # dashboards → GlobalConfig → installation_configs) query tables that don't
  # exist yet, hard-failing the boot of rake db tasks. On a migrated DB this guard
  # is a no-op.
  db_ready = begin
    ActiveRecord::Base.connection.table_exists?('installation_configs')
  rescue StandardError
    false
  end

  if db_ready
    Jabvox::ExternalExport::Catalog.reset!
    Jabvox::ExternalExport::Catalog.exportable_models.each do |model|
      model.include Jabvox::ExportableToExternalDb
      # Auto-fill created_by from Current.user on create, for models that have the
      # column (so the export always records WHO created each record).
      model.include Jabvox::TracksCreator if model.column_names.include?('created_by_id')
    rescue StandardError => e
      Rails.logger.error("[ExternalExport] could not hook #{model}: #{e.message}")
    end
  end
end
