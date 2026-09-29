# frozen_string_literal: true

# Franja de horario comercial de una sede, en minutos desde medianoche y en la zona de la
# sede. Hay una fila por franja, así que una jornada partida (8-14 y 16-20) son dos filas
# del mismo día.
# == Schema Information
#
# Table name: jabvox_branch_hours
#
#  id           :bigint           not null, primary key
#  close_minute :integer          not null
#  day_of_week  :integer          not null
#  open_minute  :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  branch_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_branch_hours_on_branch_id_and_day_of_week  (branch_id,day_of_week)
#
# Foreign Keys
#
#  fk_rails_...  (branch_id => jabvox_branches.id)
#
class JabvoxBranchHour < ApplicationRecord
  self.table_name = 'jabvox_branch_hours'

  MINUTES_IN_DAY = 1440

  belongs_to :branch, class_name: 'JabvoxBranch'

  # 0 = domingo, como Date#wday.
  validates :day_of_week, inclusion: { in: 0..6 }
  validates :open_minute, :close_minute,
            numericality: { only_integer: true, greater_than_or_equal_to: 0,
                            less_than_or_equal_to: MINUTES_IN_DAY }
  validate :close_after_open

  scope :for_day, ->(day) { where(day_of_week: day).order(:open_minute) }

  private

  def close_after_open
    return if open_minute.blank? || close_minute.blank? || close_minute > open_minute

    errors.add(:close_minute, 'debe ser posterior a la hora de apertura')
  end
end
