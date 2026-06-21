# Shares a dashboard with a user, role or team at a given access level.
# == Schema Information
#
# Table name: jabvox_analytics_shares
#
#  id                  :bigint           not null, primary key
#  access_level_jabvox :string           not null
#  subject_id_jabvox   :bigint           not null
#  subject_type_jabvox :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  created_by_id       :bigint
#  dashboard_id        :bigint           not null
#
# Indexes
#
#  idx_jabvox_analytics_shares_unique              (dashboard_id,subject_type_jabvox,subject_id_jabvox) UNIQUE
#  index_jabvox_analytics_shares_on_account_id     (account_id)
#  index_jabvox_analytics_shares_on_created_by_id  (created_by_id)
#  index_jabvox_analytics_shares_on_dashboard_id   (dashboard_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (dashboard_id => jabvox_analytics_dashboards.id)
#
class JabvoxAnalyticsShare < ApplicationRecord
  self.table_name = 'jabvox_analytics_shares'

  SUBJECT_TYPES = %w[user role team].freeze
  ACCESS_LEVELS = %w[view edit admin].freeze
  ACCESS_RANK = { 'view' => 1, 'edit' => 2, 'admin' => 3 }.freeze

  belongs_to :account
  belongs_to :dashboard, class_name: 'JabvoxAnalyticsDashboard'
  belongs_to :created_by, class_name: 'User', optional: true

  validates :subject_type_jabvox, inclusion: { in: SUBJECT_TYPES }
  validates :access_level_jabvox, inclusion: { in: ACCESS_LEVELS }
  validates :subject_id_jabvox, uniqueness: { scope: %i[dashboard_id subject_type_jabvox] }

  def rank
    ACCESS_RANK[access_level_jabvox].to_i
  end
end
