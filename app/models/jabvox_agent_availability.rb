# Horario laboral de un agente para un día de la semana. Base para calcular los
# huecos libres que Jabvox IA ofrece al agendar citas: la franja [start_minute,
# end_minute) menos las citas ya agendadas de ese agente, troceada en slots de
# slot_minutes. Sin fila para un (agente, día) => ese día el agente no atiende.
# == Schema Information
#
# Table name: jabvox_agent_availabilities
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  day_of_week  :integer          not null
#  end_minute   :integer          not null
#  slot_minutes :integer          default(30), not null
#  start_minute :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  branch_id    :bigint
#  user_id      :bigint
#
# Indexes
#
#  index_jabvox_agent_availabilities_on_account_id  (account_id)
#  index_jabvox_agent_availabilities_on_branch_id   (branch_id)
#  index_jabvox_agent_availabilities_on_user_id     (user_id)
#  index_jabvox_availabilities_lookup               (account_id,branch_id,user_id,day_of_week)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (branch_id => jabvox_branches.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAgentAvailability < ApplicationRecord
  belongs_to :account
  # Sede donde el agente cubre este tramo. Sin sede = vale para toda la cuenta, que es el
  # caso por defecto de quien solo tiene un sitio.
  belongs_to :branch, class_name: 'JabvoxBranch', optional: true
  # user opcional: una fila SIN user (user_id NULL) es el horario de EMPRESA por
  # defecto, usado como fallback para agentes sin horario propio.
  belongs_to :user, optional: true

  # Ya no hay unicidad por día: un agente puede cubrir varios tramos el mismo día (mañana
  # y tarde con pausa de comida). Lo que no puede es solaparse consigo mismo.
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :start_minute, :end_minute, presence: true,
                                        numericality: { only_integer: true, in: 0..1440 }
  validates :slot_minutes, numericality: { only_integer: true, greater_than: 0 }
  validate :no_overlap
  validate :end_after_start

  scope :active, -> { where(active: true) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :company_wide, -> { where(user_id: nil) }
  scope :for_day, ->(wday) { where(day_of_week: wday) }

  private

  # Dos tramos del mismo agente, el mismo día y en la misma sede no pueden pisarse: si lo
  # hicieran, el cálculo de huecos ofrecería la misma hora dos veces.
  def no_overlap
    return if start_minute.blank? || end_minute.blank?

    siblings = self.class.where(account_id: account_id, user_id: user_id,
                                branch_id: branch_id, day_of_week: day_of_week)
    siblings = siblings.where.not(id: id) if persisted?
    overlap = siblings.where('start_minute < ? AND end_minute > ?', end_minute, start_minute)

    errors.add(:base, 'se solapa con otro tramo del mismo día') if overlap.exists?
  end

  def end_after_start
    return if start_minute.blank? || end_minute.blank?
    return if end_minute > start_minute

    errors.add(:end_minute, 'debe ser mayor que la hora de inicio')
  end
end
