# Guards account creation against two ways the ACCOUNT_LEVEL_FEATURE_DEFAULTS
# installation config can crash Account creation with an HTTP 500:
#
# 1. bigint overflow — FlagShihTzu stores each feature as a bit in the signed
#    bigint `feature_flags` column (max 2**63 - 1). Upstream Chatwoot now has
#    more than 63 features, so any default feature at bit >= 64 (e.g.
#    captain_tasks) produces a value too large for the column ->
#    ActiveModel::RangeError.
# 2. unknown feature — a default whose name is not declared in config/features.yml
#    (e.g. a leftover from another version) has no `feature_<name>=` setter ->
#    NoMethodError.
#
# This guard filters both cases out before enabling defaults, so account
# creation stays resilient regardless of what the DB config says — the 500
# cannot come back after a redeploy, dump restore or config reseed.
module Jabvox::AccountFeatureFlagGuard
  extend ActiveSupport::Concern

  # Highest bit position that still fits in a signed bigint. Bit N maps to the
  # value 2**(N-1); the sign bit (2**63) lives at bit 64, so bits >= 64 overflow.
  MAX_SAFE_FEATURE_BIT = 63

  # Feature names (without the "feature_" prefix) whose bit does not fit in the
  # signed bigint column and therefore must never be toggled on.
  def jabvox_overflowing_feature_names
    self.class::FEATURES.select { |bit, _name| bit > MAX_SAFE_FEATURE_BIT }
                        .values.map { |sym| sym.to_s.delete_prefix('feature_') }
  end

  # Drop features that would overflow the column or that this build does not
  # define, then delegate to the core implementation.
  def enable_features(*names)
    unsafe = jabvox_overflowing_feature_names
    safe = names.map(&:to_s).select do |name|
      !unsafe.include?(name) && respond_to?("feature_#{name}=")
    end
    super(*safe)
  end
end
