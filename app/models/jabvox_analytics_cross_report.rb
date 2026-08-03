# A cross-source report: joins data pulled from several external data sources that
# live on different servers (so they can't be JOINed in native SQL). Holds the
# participating sources and the relations (mapping by a common field) between them.
# Scoped by account.
# == Schema Information
#
# Table name: jabvox_analytics_cross_reports
#
#  id                 :bigint           not null, primary key
#  description_jabvox :text
#  name_jabvox        :string           not null
#  row_limit_jabvox   :integer          default(1000), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#
# Indexes
#
#  index_jabvox_analytics_cross_reports_on_account_id     (account_id)
#  index_jabvox_analytics_cross_reports_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxAnalyticsCrossReport < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :cross_sources, class_name: 'JabvoxAnalyticsCrossSource',
                           foreign_key: :cross_report_id, dependent: :destroy, inverse_of: :cross_report
  has_many :cross_joins, class_name: 'JabvoxAnalyticsCrossJoin',
                         foreign_key: :cross_report_id, dependent: :destroy, inverse_of: :cross_report

  validates :name_jabvox, presence: true
  validates :row_limit_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 100_000 }

  # Effective per-source row cap so no single source pulls an unbounded set into
  # memory before the in-app join. Kept well above row_limit so filtering happens
  # on the join result, not by starving a source.
  def per_source_cap
    [row_limit_jabvox.to_i * 10, 50_000].min
  end
end
