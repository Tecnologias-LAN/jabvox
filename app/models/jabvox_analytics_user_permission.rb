# Assigns a user an analytics role within an account, with optional granular overrides
# (e.g. { "use_custom_sql" => true }) that take precedence over the role's grants.
# == Schema Information
#
# Table name: jabvox_analytics_user_permissions
#
#  id               :bigint           not null, primary key
#  overrides_jabvox :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  role_id          :bigint
#  user_id          :bigint           not null
#
# Indexes
#
#  idx_on_account_id_user_id_d329916899                   (account_id,user_id) UNIQUE
#  index_jabvox_analytics_user_permissions_on_account_id  (account_id)
#  index_jabvox_analytics_user_permissions_on_role_id     (role_id)
#  index_jabvox_analytics_user_permissions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (role_id => jabvox_analytics_roles.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAnalyticsUserPermission < ApplicationRecord
  self.table_name = 'jabvox_analytics_user_permissions'

  belongs_to :account
  belongs_to :user
  belongs_to :role, class_name: 'JabvoxAnalyticsRole', optional: true

  validates :user_id, uniqueness: { scope: :account_id }
  validate :overrides_keys_valid

  private

  def overrides_keys_valid
    return if overrides_jabvox.blank?

    invalid = overrides_jabvox.keys.map(&:to_s) - JabvoxAnalyticsPermission::KEYS
    errors.add(:overrides_jabvox, "contains unknown keys: #{invalid.join(', ')}") if invalid.any?
  end
end
