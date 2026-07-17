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

  # Shared SSRF/host guard for every write path (schema build, row export,
  # backfill, test connection). The target's configured port is explicitly
  # allowed — it's a destination the admin set up on purpose, not an arbitrary
  # SSRF target — so customer DBs on non-standard ports (e.g. 5438) work, while
  # private-network and cloud-metadata protections still apply unless the admin
  # opted in.
  #
  # Returns the list of validated IPs so the caller can connect to a
  # already-checked address instead of re-resolving the hostname (which would
  # reopen a DNS-rebinding hole). Raises ConnectionError when the host is unsafe.
  def guard!(target)
    result = Jabvox::Analytics::HostGuardService.new(
      host: target.host_jabvox,
      port: target.effective_port,
      allow_private: target.allow_private_network_jabvox,
      allowed_ports: (Jabvox::Analytics::HostGuardService::DEFAULT_ALLOWED_PORTS +
                      [target.effective_port.to_i]).uniq
    ).call
    raise Jabvox::ExternalExport::WriteAdapter::ConnectionError, result.reason unless result.allowed?

    result.resolved_ips
  end
end
