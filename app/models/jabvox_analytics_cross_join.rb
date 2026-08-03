# A relation between two participating sources: which column of the left source
# maps to which column of the right source, and the join type. This is the
# "mapping by a common field" — e.g. ventas.tienda_id ↔ tiendas.id.
# == Schema Information
#
# Table name: jabvox_analytics_cross_joins
#
#  id                  :bigint           not null, primary key
#  join_type_jabvox    :string           default("inner"), not null
#  left_column_jabvox  :string           not null
#  position_jabvox     :integer          default(0), not null
#  right_column_jabvox :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  cross_report_id     :bigint           not null
#  left_source_id      :bigint           not null
#  right_source_id     :bigint           not null
#
# Indexes
#
#  index_jabvox_analytics_cross_joins_on_cross_report_id  (cross_report_id)
#  index_jabvox_analytics_cross_joins_on_left_source_id   (left_source_id)
#  index_jabvox_analytics_cross_joins_on_right_source_id  (right_source_id)
#
# Foreign Keys
#
#  fk_rails_...  (cross_report_id => jabvox_analytics_cross_reports.id)
#  fk_rails_...  (left_source_id => jabvox_analytics_cross_sources.id)
#  fk_rails_...  (right_source_id => jabvox_analytics_cross_sources.id)
#
class JabvoxAnalyticsCrossJoin < ApplicationRecord
  JOIN_TYPES = %w[inner left].freeze

  belongs_to :cross_report, class_name: 'JabvoxAnalyticsCrossReport', inverse_of: :cross_joins
  belongs_to :left_source, class_name: 'JabvoxAnalyticsCrossSource'
  belongs_to :right_source, class_name: 'JabvoxAnalyticsCrossSource'

  validates :left_column_jabvox, :right_column_jabvox, presence: true
  validates :join_type_jabvox, inclusion: { in: JOIN_TYPES }
  validate :sources_are_different
  validate :sources_belong_to_report

  private

  def sources_are_different
    return if left_source_id.blank? || right_source_id.blank?

    errors.add(:right_source_id, 'no puede ser la misma fuente') if left_source_id == right_source_id
  end

  def sources_belong_to_report
    [left_source, right_source].compact.each do |src|
      errors.add(:base, 'la fuente no pertenece al reporte') if src.cross_report_id != cross_report_id
    end
  end
end
