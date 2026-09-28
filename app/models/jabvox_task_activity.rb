# Append-only history of changes to a task. Written by the controller via
# JabvoxTask#log_activity. Mirrors the analytics audit-log pattern (no updated_at).
# == Schema Information
#
# Table name: jabvox_task_activities
#
#  id              :bigint           not null, primary key
#  action_jabvox   :string           not null
#  metadata_jabvox :jsonb            not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  task_id         :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  index_jabvox_task_activities_on_account_id            (account_id)
#  index_jabvox_task_activities_on_account_task_created  (account_id,task_id,created_at)
#  index_jabvox_task_activities_on_task_id               (task_id)
#  index_jabvox_task_activities_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxTaskActivity < ApplicationRecord
  self.table_name = 'jabvox_task_activities'

  # No updated_at column: this table is append-only.
  self.record_timestamps = false

  # Recognized activity kinds. Free-form metadata carries the specifics (from/to, names…).
  # Tipos reconocidos. El metadata libre lleva los detalles (from/to, nombres, texto...).
  #
  # `comment` es el único que escribe una persona: el resto los genera el sistema al
  # cambiar un campo. Guardar el comentario aquí y no en una tabla aparte hace que la
  # conversación de resolución y los cambios de la tarea se lean en un mismo hilo, que es
  # como se sigue un caso.
  COMMENT = 'comment'.freeze
  ACTIONS = %w[
    created stage_changed status_changed priority_changed due_date_changed
    title_changed description_changed assignee_added assignee_removed
    lead_changed recurrence_created comment
  ].freeze

  MAX_COMMENT_LENGTH = 5000

  scope :comments, -> { where(action_jabvox: COMMENT) }

  def comment?
    action_jabvox == COMMENT
  end

  def body
    metadata_jabvox['body'].to_s
  end

  belongs_to :account
  belongs_to :task, class_name: 'JabvoxTask'
  belongs_to :user, optional: true

  validates :action_jabvox, presence: true

  before_validation :stamp_created_at, on: :create

  scope :recent, -> { order(created_at: :desc) }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
