# A single widget on a dashboard. Holds either a visual query spec or custom SQL plus viz config.
# == Schema Information
#
# Table name: jabvox_analytics_dashboard_widgets
#
#  id                 :bigint           not null, primary key
#  config_jabvox      :jsonb            not null
#  custom_sql_jabvox  :text
#  position_jabvox    :integer          default(0), not null
#  query_spec_jabvox  :jsonb            not null
#  title_jabvox       :string           default(""), not null
#  widget_type_jabvox :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  dashboard_id       :bigint           not null
#  data_source_id     :bigint
#
# Indexes
#
#  idx_on_account_id_dashboard_id_0dbd985dda                   (account_id,dashboard_id)
#  index_jabvox_analytics_dashboard_widgets_on_account_id      (account_id)
#  index_jabvox_analytics_dashboard_widgets_on_dashboard_id    (dashboard_id)
#  index_jabvox_analytics_dashboard_widgets_on_data_source_id  (data_source_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (dashboard_id => jabvox_analytics_dashboards.id)
#  fk_rails_...  (data_source_id => jabvox_analytics_data_sources.id)
#
class JabvoxAnalyticsDashboardWidget < ApplicationRecord
  self.table_name = 'jabvox_analytics_dashboard_widgets'

  # The ~19 supported widget types.
  WIDGET_TYPES = %w[
    table pivot_table number indicator ranking comparative
    line area time_series bar stacked_bar pie donut scatter gauge
    heatmap treemap funnel map text_markdown
  ].freeze

  belongs_to :account
  belongs_to :dashboard, class_name: 'JabvoxAnalyticsDashboard'
  belongs_to :data_source, class_name: 'JabvoxAnalyticsDataSource', optional: true

  has_many :filters, class_name: 'JabvoxAnalyticsWidgetFilter', foreign_key: :widget_id,
                     dependent: :destroy, inverse_of: :widget

  validates :widget_type_jabvox, inclusion: { in: WIDGET_TYPES }

  scope :ordered, -> { order(:position_jabvox) }

  def uses_custom_sql?
    custom_sql_jabvox.present?
  end
end
