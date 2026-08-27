# Syncs all of an account's WhatsApp Cloud inboxes with Meta off the request cycle, so opening
# the templates module (or hitting "sync") refreshes statuses without blocking the UI.
class Jabvox::WhatsappTemplatesSyncAllJob < ApplicationJob
  queue_as :jabvox_meta

  def perform(account_id, only_stale: false)
    account = Account.find_by(id: account_id)
    return unless account
    return unless account.feature_enabled?('jabvox_whatsapp_templates')

    Jabvox::WhatsappTemplatesManager.new(account).sync_all_inboxes(only_stale: only_stale)
  end
end
