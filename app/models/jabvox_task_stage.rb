# A column on a task board.
# == Schema Information
#
# Table name: jabvox_task_stages
#
#  id              :bigint           not null, primary key
#  color_jabvox    :string           default("#6b7280"), not null
#  name_jabvox     :string           not null
#  position_jabvox :integer          default(0), not null
#  role_jabvox     :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  board_id        :bigint           not null
#  created_by_id   :bigint
#
# Indexes
#
#  index_jabvox_task_stages_on_account_id                    (account_id)
#  index_jabvox_task_stages_on_board_and_role                (board_id,role_jabvox) UNIQUE WHERE (role_jabvox IS NOT NULL)
#  index_jabvox_task_stages_on_board_id                      (board_id)
#  index_jabvox_task_stages_on_board_id_and_position_jabvox  (board_id,position_jabvox)
#  index_jabvox_task_stages_on_created_by_id                 (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => jabvox_task_boards.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxTaskStage < ApplicationRecord
  # Papel de la etapa en el flujo. NULL = columna intermedia normal.
  #   initial  — donde nace una tarea (y donde reaparece una recurrente)
  #   done     — completada
  #   inactive — se dejó vencer sin hacer
  # Solo puede haber una de cada por tablero (índice único parcial en la migración).
  ROLES = %w[initial done inactive].freeze

  validates :role_jabvox, inclusion: { in: ROLES }, allow_blank: true
  self.table_name = 'jabvox_task_stages'

  belongs_to :account
  belongs_to :board, class_name: 'JabvoxTaskBoard'

  # stage_id es NOT NULL: una tarea no puede quedar sin stage. Al borrar un stage se destruyen
  # sus tareas (nullify violaría la FK NOT NULL y reventaba el borrado del board — 500).
  has_many :tasks, class_name: 'JabvoxTask', foreign_key: :stage_id,
                   dependent: :destroy, inverse_of: :stage
  has_many :automations, class_name: 'JabvoxTaskStageAutomation', foreign_key: :stage_id,
                         dependent: :destroy, inverse_of: :stage
  # Automations on other stages that move tasks INTO this stage lose their
  # target instead of blocking the deletion.
  has_many :incoming_automations, class_name: 'JabvoxTaskStageAutomation', foreign_key: :target_stage_id,
                                  dependent: :nullify, inverse_of: false

  validates :name_jabvox, presence: true

  scope :ordered, -> { order(:position_jabvox) }
end
