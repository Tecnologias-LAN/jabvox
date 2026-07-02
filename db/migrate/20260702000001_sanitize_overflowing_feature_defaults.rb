# Disables any account-level default feature whose FlagShihTzu bit does not fit
# in the signed bigint `feature_flags` column (bit >= 64). Leaving such a
# feature enabled by default makes Account creation raise ActiveModel::RangeError
# (HTTP 500). Idempotent and data-only; safe to run on any environment.
class SanitizeOverflowingFeatureDefaults < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank?

    overflowing = overflowing_feature_names
    return if overflowing.empty?

    cleaned = config.value.map { |feature| disable_if_overflowing(feature, overflowing) }
    config.update!(value: cleaned) if cleaned != config.value
  end

  def down
    # No-op: re-enabling overflowing defaults would reintroduce the 500.
  end

  private

  # Returns the feature with enabled:false if it overflows and was on; else as-is.
  def disable_if_overflowing(feature, overflowing)
    name = (feature['name'] || feature[:name]).to_s
    enabled = feature['enabled'] || feature[:enabled]
    return feature unless overflowing.include?(name) && enabled

    feature.merge('enabled' => false)
  end

  # Feature names (without the "feature_" prefix) whose bit overflows bigint.
  def overflowing_feature_names
    Account::FEATURES.select { |bit, _name| bit > Jabvox::AccountFeatureFlagGuard::MAX_SAFE_FEATURE_BIT }
                     .values.map { |sym| sym.to_s.delete_prefix('feature_') }
  end
end
