# A filter definition, either dashboard-global or scoped to a single widget.
# == Schema Information
#
# Table name: jabvox_analytics_widget_filters
#
#  id                 :bigint           not null, primary key
#  field_jabvox       :string           not null
#  filter_type_jabvox :string           not null
#  is_global_jabvox   :boolean          default(FALSE), not null
#  operator_jabvox    :string           not null
#  position_jabvox    :integer          default(0), not null
#  value_jabvox       :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  dashboard_id       :bigint
#  widget_id          :bigint
#
# Indexes
#
#  idx_on_account_id_dashboard_id_9c660e1919              (account_id,dashboard_id)
#  idx_on_account_id_widget_id_9ad6238e06                 (account_id,widget_id)
#  index_jabvox_analytics_widget_filters_on_account_id    (account_id)
#  index_jabvox_analytics_widget_filters_on_dashboard_id  (dashboard_id)
#  index_jabvox_analytics_widget_filters_on_widget_id     (widget_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (dashboard_id => jabvox_analytics_dashboards.id)
#  fk_rails_...  (widget_id => jabvox_analytics_dashboard_widgets.id)
#
class JabvoxAnalyticsWidgetFilter < ApplicationRecord
  self.table_name = 'jabvox_analytics_widget_filters'

  FILTER_TYPES = %w[date_range select multiselect text number].freeze
  OPERATORS = %w[eq neq gt gte lt lte between in contains starts_with].freeze

  belongs_to :account
  belongs_to :dashboard, class_name: 'JabvoxAnalyticsDashboard', optional: true
  belongs_to :widget, class_name: 'JabvoxAnalyticsDashboardWidget', optional: true

  validates :field_jabvox, presence: true
  validates :operator_jabvox, inclusion: { in: OPERATORS }
  validates :filter_type_jabvox, inclusion: { in: FILTER_TYPES }
  validate :dashboard_or_widget_present

  scope :global, -> { where(is_global_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox) }

  private

  def dashboard_or_widget_present
    return if dashboard_id.present? || widget_id.present?

    errors.add(:base, 'Either a dashboard or a widget must be set')
  end
end
