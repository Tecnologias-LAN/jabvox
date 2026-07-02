# A single permission grant for a role. KEYS is the full catalog of capabilities.
# == Schema Information
#
# Table name: jabvox_analytics_permissions
#
#  id                    :bigint           not null, primary key
#  granted_jabvox        :boolean          default(FALSE), not null
#  permission_key_jabvox :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  role_id               :bigint           not null
#
# Indexes
#
#  idx_jabvox_analytics_perms_unique                 (account_id,role_id,permission_key_jabvox) UNIQUE
#  index_jabvox_analytics_permissions_on_account_id  (account_id)
#  index_jabvox_analytics_permissions_on_role_id     (role_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (role_id => jabvox_analytics_roles.id)
#
class JabvoxAnalyticsPermission < ApplicationRecord
  self.table_name = 'jabvox_analytics_permissions'

  KEYS = %w[
    access create edit_own edit_all delete_own delete_all
    share view_all_data manage_data_sources use_custom_sql
  ].freeze

  belongs_to :account
  belongs_to :role, class_name: 'JabvoxAnalyticsRole'

  validates :permission_key_jabvox, presence: true, inclusion: { in: KEYS },
                                    uniqueness: { scope: %i[account_id role_id] }
end
