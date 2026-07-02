# An RBAC role within the Analytics module for an account.
# The 4 system roles (admin/supervisor/analyst/viewer) are seeded and not deletable.
# == Schema Information
#
# Table name: jabvox_analytics_roles
#
#  id                 :bigint           not null, primary key
#  description_jabvox :string           default(""), not null
#  is_system_jabvox   :boolean          default(FALSE), not null
#  name_jabvox        :string           not null
#  slug_jabvox        :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_analytics_roles_on_account_id                  (account_id)
#  index_jabvox_analytics_roles_on_account_id_and_slug_jabvox  (account_id,slug_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAnalyticsRole < ApplicationRecord
  self.table_name = 'jabvox_analytics_roles'

  # Default per-role grants seeded for the 4 system roles. Defined as a method (not a
  # load-time constant) so it doesn't depend on JabvoxAnalyticsPermission being loaded first.
  def self.system_role_defaults
    {
      'admin' => { name: 'Admin', permissions: JabvoxAnalyticsPermission::KEYS },
      'supervisor' => { name: 'Supervisor',
                        permissions: %w[access create edit_own edit_all delete_own share view_all_data manage_data_sources use_custom_sql] },
      'analyst' => { name: 'Analyst', permissions: %w[access create edit_own delete_own use_custom_sql] },
      'viewer' => { name: 'Viewer', permissions: %w[access] }
    }
  end

  belongs_to :account
  has_many :permissions, class_name: 'JabvoxAnalyticsPermission',
                         foreign_key: :role_id, dependent: :destroy, inverse_of: :role
  has_many :user_permissions, class_name: 'JabvoxAnalyticsUserPermission',
                              foreign_key: :role_id, dependent: :nullify, inverse_of: :role

  validates :name_jabvox, presence: true
  validates :slug_jabvox, presence: true, uniqueness: { scope: :account_id }

  scope :system, -> { where(is_system_jabvox: true) }
  scope :custom, -> { where(is_system_jabvox: false) }

  # Map of permission_key => granted boolean for this role.
  def grants
    permissions.pluck(:permission_key_jabvox, :granted_jabvox).to_h
  end
end
