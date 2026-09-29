# frozen_string_literal: true

# Sede donde se atiende: consultorio, sucursal, local… el nombre lo pone cada cliente.
#
# Aporta dos cosas al calendario: la ZONA HORARIA con la que se interpretan sus horarios, y
# el HORARIO COMERCIAL que se sombrea en la agenda. Los agentes cubren tramos dentro de ese
# horario (ver JabvoxAgentAvailability), así que la sede dice cuándo está abierto y el
# agente cuándo está él.
# == Schema Information
#
# Table name: jabvox_branches
#
#  id              :bigint           not null, primary key
#  active_jabvox   :boolean          default(TRUE), not null
#  address_jabvox  :text
#  color_jabvox    :string           default("#6366F1"), not null
#  name_jabvox     :string           not null
#  position_jabvox :integer          default(0), not null
#  timezone_jabvox :string           default("UTC"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#
# Indexes
#
#  index_jabvox_branches_on_account_id                  (account_id)
#  index_jabvox_branches_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_branches_on_created_by_id               (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxBranch < ApplicationRecord
  self.table_name = 'jabvox_branches'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :managers, class_name: 'JabvoxBranchManager', foreign_key: :branch_id,
                      dependent: :destroy, inverse_of: :branch
  has_many :manager_users, through: :managers, source: :user
  has_many :hours, class_name: 'JabvoxBranchHour', foreign_key: :branch_id,
                   dependent: :destroy, inverse_of: :branch
  # Los horarios de agente y las citas se quedan sin sede en vez de borrarse: perder una
  # agenda entera por cerrar una sede sería peor que dejarla huérfana.
  has_many :agent_availabilities, class_name: 'JabvoxAgentAvailability', foreign_key: :branch_id,
                                  dependent: :nullify, inverse_of: :branch
  has_many :calendar_events, class_name: 'JabvoxCalendarEvent', foreign_key: :branch_id,
                             dependent: :nullify, inverse_of: :branch

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validate :timezone_is_known

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }

  def time_zone
    ActiveSupport::TimeZone[timezone_jabvox.to_s] || ActiveSupport::TimeZone['UTC']
  end

  private

  # Solo zonas que Rails sepa resolver: una cadena inventada haría que el horario comercial
  # se calculara en UTC sin avisar.
  def timezone_is_known
    return if ActiveSupport::TimeZone[timezone_jabvox.to_s].present?

    errors.add(:timezone_jabvox, 'no es una zona horaria conocida')
  end
end
