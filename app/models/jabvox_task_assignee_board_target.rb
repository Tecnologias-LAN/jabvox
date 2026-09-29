# A qué tablero se copia una tarea cuando se le asigna un responsable que es dueño de
# tablero. Una fila por (tablero de origen, dueño): un usuario puede ser dueño de varios
# tableros, así que el destino se elige explícitamente en vez de adivinarlo.
# == Schema Information
#
# Table name: jabvox_task_assignee_board_targets
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  owner_id        :bigint           not null
#  source_board_id :bigint           not null
#  target_board_id :bigint           not null
#
# Indexes
#
#  index_jabvox_task_assignee_board_targets_on_account_id       (account_id)
#  index_jabvox_task_assignee_board_targets_on_owner_id         (owner_id)
#  index_jabvox_task_assignee_board_targets_on_source_board_id  (source_board_id)
#  index_jabvox_task_assignee_board_targets_on_target_board_id  (target_board_id)
#  index_jabvox_task_targets_on_source_and_owner                (source_board_id,owner_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (source_board_id => jabvox_task_boards.id)
#  fk_rails_...  (target_board_id => jabvox_task_boards.id)
#
class JabvoxTaskAssigneeBoardTarget < ApplicationRecord
  include Jabvox::AccountScopedReferences

  self.table_name = 'jabvox_task_assignee_board_targets'

  belongs_to :account
  belongs_to :source_board, class_name: 'JabvoxTaskBoard'
  belongs_to :owner, class_name: 'User'
  belongs_to :target_board, class_name: 'JabvoxTaskBoard'

  # Los tres apuntan a la misma cuenta que la fila: sin esto se podía mandar la copia al
  # tablero de otro cliente.
  validates_account_scope :source_board, :target_board

  validates :owner_id, uniqueness: { scope: :source_board_id }
  validate :target_board_belongs_to_owner
  validate :owner_belongs_to_account

  private

  # El destino tiene que ser un tablero del propio dueño: elegir el de otro convertiría la
  # automatización en una vía para meter tareas en tableros ajenos.
  def target_board_belongs_to_owner
    return if target_board.nil? || owner_id.nil?
    return if target_board.owner_id == owner_id

    errors.add(:target_board, 'debe ser un tablero del responsable')
  end

  def owner_belongs_to_account
    return if owner_id.nil? || account_id.nil?
    return if AccountUser.exists?(account_id: account_id, user_id: owner_id)

    errors.add(:owner, 'no pertenece a la cuenta')
  end
end
