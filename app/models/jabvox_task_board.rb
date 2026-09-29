# A kanban board of tasks for an account (e.g. "Operaciones").
# == Schema Information
#
# Table name: jabvox_task_boards
#
#  id                            :bigint           not null, primary key
#  copy_to_assignee_board_jabvox :boolean          default(FALSE), not null
#  description_jabvox            :text
#  is_active_jabvox              :boolean          default(TRUE), not null
#  name_jabvox                   :string           not null
#  position_jabvox               :integer          default(0), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  created_by_id                 :bigint
#  owner_id                      :bigint
#
# Indexes
#
#  index_jabvox_task_boards_on_account_id                  (account_id)
#  index_jabvox_task_boards_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_task_boards_on_created_by_id               (created_by_id)
#  index_jabvox_task_boards_on_owner_id                    (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (owner_id => users.id)
#
class JabvoxTaskBoard < ApplicationRecord
  self.table_name = 'jabvox_task_boards'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  # Dueño del tablero: a quién pertenece como "tablero personal". Sirve de destino cuando
  # otro tablero tiene activada la copia por responsable.
  belongs_to :owner, class_name: 'User', optional: true

  has_many :stages, class_name: 'JabvoxTaskStage', foreign_key: :board_id,
                    dependent: :destroy, inverse_of: :board
  has_many :tasks, class_name: 'JabvoxTask', foreign_key: :board_id,
                   dependent: :destroy, inverse_of: :board
  # Destinos configurados en ESTE tablero: a qué tablero va la copia de cada dueño.
  has_many :assignee_board_targets, class_name: 'JabvoxTaskAssigneeBoardTarget',
                                    foreign_key: :source_board_id, dependent: :destroy,
                                    inverse_of: :source_board
  # Filas que apuntan a este tablero como destino: se van con él para no dejar la
  # automatización apuntando a un tablero borrado.
  has_many :incoming_board_targets, class_name: 'JabvoxTaskAssigneeBoardTarget',
                                    foreign_key: :target_board_id, dependent: :destroy,
                                    inverse_of: :target_board

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(is_active_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
end
