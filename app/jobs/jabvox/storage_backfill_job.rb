# Backfills Audio Analysis <-> AI Chat storages for an account once both modules
# are enabled, so each side ends up with every storage the other has. Runs off
# the request cycle (triggered when a module flag flips to enabled).
class Jabvox::StorageBackfillJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    Jabvox::StorageSyncService.mirror_all(account)
  end
end
