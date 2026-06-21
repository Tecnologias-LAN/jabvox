# An export job (PDF/Excel/CSV) of a dashboard and its status/result.
# == Schema Information
#
# Table name: jabvox_analytics_exports
#
#  id                :bigint           not null, primary key
#  error_jabvox      :text
#  expires_at_jabvox :datetime
#  file_url_jabvox   :string
#  format_jabvox     :string           not null
#  params_jabvox     :jsonb            not null
#  status_jabvox     :string           default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  dashboard_id      :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_jabvox_analytics_exports_on_account_id                    (account_id)
#  index_jabvox_analytics_exports_on_account_id_and_status_jabvox  (account_id,status_jabvox)
#  index_jabvox_analytics_exports_on_dashboard_id                  (dashboard_id)
#  index_jabvox_analytics_exports_on_user_id                       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (dashboard_id => jabvox_analytics_dashboards.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAnalyticsExport < ApplicationRecord
  self.table_name = 'jabvox_analytics_exports'

  FORMATS = %w[pdf excel csv].freeze
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :account
  belongs_to :dashboard, class_name: 'JabvoxAnalyticsDashboard', optional: true
  belongs_to :user

  has_one_attached :file

  validates :format_jabvox, inclusion: { in: FORMATS }
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
end
