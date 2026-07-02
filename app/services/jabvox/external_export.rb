# Namespace + cheap gate used on every exportable record's after_commit. Caches
# "does this account export?" briefly so hot write paths don't hit the DB each time.
module Jabvox::ExternalExport
  ENABLED_TTL = 60 # seconds

  module_function

  def export_enabled?(account_id)
    Rails.cache.fetch("jabvox_export_enabled/#{account_id}", expires_in: ENABLED_TTL) do
      account = Account.find_by(id: account_id)
      next false unless account&.feature_enabled?('jabvox_data_export')

      account.jabvox_export_targets.active.exists?
    end
  rescue StandardError
    false
  end

  # Call after enabling/disabling or changing the target so the gate refreshes now.
  def bust_cache(account_id)
    Rails.cache.delete("jabvox_export_enabled/#{account_id}")
  end
end
