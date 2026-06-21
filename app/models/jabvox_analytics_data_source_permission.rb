# Grants a user or role the ability to query a specific data source (and optionally run custom SQL).
# == Schema Information
#
# Table name: jabvox_analytics_data_source_permissions
#
#  id                        :bigint           not null, primary key
#  can_query_jabvox          :boolean          default(TRUE), not null
#  can_use_custom_sql_jabvox :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  data_source_id            :bigint           not null
#  role_id                   :bigint
#  user_id                   :bigint
#
# Indexes
#
#  idx_jabvox_analytics_dsp_role                                 (data_source_id,role_id) UNIQUE
#  idx_jabvox_analytics_dsp_user                                 (data_source_id,user_id) UNIQUE
#  idx_on_data_source_id_be7ed7447f                              (data_source_id)
#  index_jabvox_analytics_data_source_permissions_on_account_id  (account_id)
#  index_jabvox_analytics_data_source_permissions_on_role_id     (role_id)
#  index_jabvox_analytics_data_source_permissions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (data_source_id => jabvox_analytics_data_sources.id)
#  fk_rails_...  (role_id => jabvox_analytics_roles.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAnalyticsDataSourcePermission < ApplicationRecord
  self.table_name = 'jabvox_analytics_data_source_permissions'

  belongs_to :account
  belongs_to :data_source, class_name: 'JabvoxAnalyticsDataSource'
  belongs_to :user, optional: true
  belongs_to :role, class_name: 'JabvoxAnalyticsRole', optional: true

  validate :user_or_role_present

  private

  def user_or_role_present
    return if user_id.present? || role_id.present?

    errors.add(:base, 'Either a user or a role must be set')
  end
end
