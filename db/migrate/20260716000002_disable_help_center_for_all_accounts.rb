class DisableHelpCenterForAllAccounts < ActiveRecord::Migration[7.1]
  # Help Center is off by default (config/features.yml) but existing accounts
  # already carry the flag in their feature bitmask. Turn it off for every account
  # that has it on. A Super Admin can re-enable it per account afterwards.
  def up
    Account.feature_help_center.find_each(batch_size: 100) do |account|
      account.disable_features(:help_center)
      account.save!(validate: false)
    end
  end

  def down
    # No-op: we don't blindly re-enable Help Center on rollback.
  end
end
