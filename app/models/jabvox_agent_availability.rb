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
#  user_id      :bigint
#
# Indexes
#
#  index_jabvox_agent_availabilities_company_unique  (account_id,day_of_week) UNIQUE WHERE (user_id IS NULL)
#  index_jabvox_agent_availabilities_on_account_id   (account_id)
#  index_jabvox_agent_availabilities_on_user_id      (user_id)
#  index_jabvox_agent_availabilities_unique          (account_id,user_id,day_of_week) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAgentAvailability < ApplicationRecord
  belongs_to :account
  # user opcional: una fila SIN user (user_id NULL) es el horario de EMPRESA por
  # defecto, usado como fallback para agentes sin horario propio.
  belongs_to :user, optional: true

  validates :day_of_week, presence: true,
                          inclusion: { in: 0..6 },
                          uniqueness: { scope: %i[account_id user_id] }
  validates :start_minute, :end_minute, presence: true,
                                        numericality: { only_integer: true, in: 0..1440 }
  validates :slot_minutes, numericality: { only_integer: true, greater_than: 0 }
  validate :end_after_start

  scope :active, -> { where(active: true) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :company_wide, -> { where(user_id: nil) }
  scope :for_day, ->(wday) { where(day_of_week: wday) }

  private

  def end_after_start
    return if start_minute.blank? || end_minute.blank?
    return if end_minute > start_minute

    errors.add(:end_minute, 'debe ser mayor que la hora de inicio')
  end
end
