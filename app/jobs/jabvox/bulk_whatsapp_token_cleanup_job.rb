# Deletes the short-lived Bulk WhatsApp access token once its TTL has elapsed. Authentication
# already rejects it once expired; this removes the row so no expired credential lingers. Safe
# to run late or twice (no-op if already gone).
class Jabvox::BulkWhatsappTokenCleanupJob < ApplicationJob
  queue_as :low

  def perform(access_token_id)
    AccessToken.where(id: access_token_id).destroy_all
  end
end
