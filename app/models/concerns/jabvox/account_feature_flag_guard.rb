# Guards account creation against a stale ACCOUNT_LEVEL_FEATURE_DEFAULTS
# installation config crashing Account creation with an HTTP 500:
#
#   unknown feature — a default whose name is not declared in config/features.yml
#   (e.g. a leftover from another version) has no `feature_<name>=` setter ->
#   NoMethodError.
#
# The bigint-overflow case this guard used to handle is now solved upstream by
# the multi-column flag mechanism (feature_flags + feature_flags_ext_1, see
# Featurable), so only the unknown-feature filter remains. Account creation stays
# resilient regardless of what the DB config says — the 500 cannot come back
# after a redeploy, dump restore or config reseed.
module Jabvox::AccountFeatureFlagGuard
  extend ActiveSupport::Concern

  # Drop features this build does not define, then delegate to the core
  # implementation.
  def enable_features(*names)
    safe = names.map(&:to_s).select { |name| respond_to?("feature_#{name}=") }
    super(*safe)
  end
end
