# One participating source in a cross-source report: a data source + a table +
# which columns to pull (empty = all) + optional row filters. The `alias_jabvox`
# qualifies its columns in the joined result (e.g. ventas.total vs tiendas.nombre),
# so the same column name in two sources doesn't collide.
# == Schema Information
#
# Table name: jabvox_analytics_cross_sources
#
#  id              :bigint           not null, primary key
#  alias_jabvox    :string           not null
#  columns_jabvox  :jsonb            not null
#  filters_jabvox  :jsonb            not null
#  position_jabvox :integer          default(0), not null
#  table_jabvox    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  cross_report_id :bigint           not null
#  data_source_id  :bigint           not null
#
# Indexes
#
#  idx_cross_sources_report_alias                           (cross_report_id,alias_jabvox) UNIQUE
#  index_jabvox_analytics_cross_sources_on_cross_report_id  (cross_report_id)
#  index_jabvox_analytics_cross_sources_on_data_source_id   (data_source_id)
#
# Foreign Keys
#
#  fk_rails_...  (cross_report_id => jabvox_analytics_cross_reports.id)
#  fk_rails_...  (data_source_id => jabvox_analytics_data_sources.id)
#
class JabvoxAnalyticsCrossSource < ApplicationRecord
  belongs_to :cross_report, class_name: 'JabvoxAnalyticsCrossReport', inverse_of: :cross_sources
  belongs_to :data_source, class_name: 'JabvoxAnalyticsDataSource'

  has_many :left_joins, class_name: 'JabvoxAnalyticsCrossJoin',
                        foreign_key: :left_source_id, dependent: :destroy, inverse_of: :left_source
  has_many :right_joins, class_name: 'JabvoxAnalyticsCrossJoin',
                         foreign_key: :right_source_id, dependent: :destroy, inverse_of: :right_source

  validates :table_jabvox, presence: true
  validates :alias_jabvox, presence: true,
                           format: { with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/ },
                           uniqueness: { scope: :cross_report_id }

  # Columns to SELECT from this source, or nil to mean "all columns".
  def selected_columns
    cols = Array(columns_jabvox).map(&:to_s).reject(&:blank?)
    cols.empty? ? nil : cols
  end

  # [{ 'column' =>, 'operator' =>, 'value' => }] normalized filters.
  def normalized_filters
    Array(filters_jabvox).filter_map do |f|
      h = f.respond_to?(:to_h) ? f.to_h.stringify_keys : {}
      next if h['column'].blank?

      { 'column' => h['column'].to_s, 'operator' => h['operator'].to_s, 'value' => h['value'] }
    end
  end
end
