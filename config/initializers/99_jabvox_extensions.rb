Rails.application.config.to_prepare do
  Conversation.include Jabvox::KanbanConversationHooks
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
  Account.prepend Jabvox::AccountResponseBotFeature
  Contact.include Jabvox::ContactLeadsIntegration
  Api::V1::Accounts::ContactsController.include Jabvox::ContactFieldProtection
end
