# A dashboard: a grid of widgets with global filters and a cache policy.
# == Schema Information
#
# Table name: jabvox_analytics_dashboards
#
#  id                       :bigint           not null, primary key
#  cache_ttl_seconds_jabvox :integer          default(300), not null
#  description_jabvox       :text
#  global_filters_jabvox    :jsonb            not null
#  is_template_jabvox       :boolean          default(FALSE), not null
#  layout_jabvox            :jsonb            not null
#  name_jabvox              :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  created_by_id            :bigint
#  folder_id                :bigint
#
# Indexes
#
#  index_jabvox_analytics_dashboards_on_account_id                (account_id)
#  index_jabvox_analytics_dashboards_on_account_id_and_folder_id  (account_id,folder_id)
#  index_jabvox_analytics_dashboards_on_created_by_id             (created_by_id)
#  index_jabvox_analytics_dashboards_on_folder_id                 (folder_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (folder_id => jabvox_analytics_folders.id)
#
class JabvoxAnalyticsDashboard < ApplicationRecord
  self.table_name = 'jabvox_analytics_dashboards'

  belongs_to :account
  belongs_to :folder, class_name: 'JabvoxAnalyticsFolder', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :widgets, class_name: 'JabvoxAnalyticsDashboardWidget', foreign_key: :dashboard_id,
                     dependent: :destroy, inverse_of: :dashboard
  has_many :filters, class_name: 'JabvoxAnalyticsWidgetFilter', foreign_key: :dashboard_id,
                     dependent: :destroy, inverse_of: :dashboard
  has_many :shares, class_name: 'JabvoxAnalyticsShare', foreign_key: :dashboard_id,
                    dependent: :destroy, inverse_of: :dashboard

  validates :name_jabvox, presence: true
  validates :cache_ttl_seconds_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :owned_by, ->(user_id) { where(created_by_id: user_id) }
end
