# Backfills CDR <-> Audio Analysis pipelines for an account once both modules
# are enabled, so each side ends up with every pipeline the other has. Runs off
# the request cycle (triggered when a module flag flips to enabled).
class Jabvox::PipelineBackfillJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    Jabvox::PipelineSyncService.mirror_all(account)
  end
end
