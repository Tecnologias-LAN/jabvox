# A task card on a board. Optionally references a lead (read-only) and an optional due date
# (used by the calendar view). Moving the card to a new stage fires that stage's automations.
# == Schema Information
#
# Table name: jabvox_tasks
#
#  id                      :bigint           not null, primary key
#  deleted_at_jabvox       :datetime
#  description_jabvox      :text
#  due_at_jabvox           :datetime
#  due_dates_jabvox        :jsonb            not null
#  position_jabvox         :integer          default(0), not null
#  priority_jabvox         :string           default("normal"), not null
#  recurrence_count_jabvox :integer          default(1), not null
#  recurrence_unit_jabvox  :string
#  recurrence_until_jabvox :datetime
#  reminder_sent_at_jabvox :datetime
#  status_jabvox           :string           default("open"), not null
#  title_jabvox            :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  assignee_id             :bigint
#  board_id                :bigint           not null
#  contact_id              :bigint
#  created_by_id           :bigint
#  recurrence_parent_id    :bigint
#  source_task_id          :bigint
#  stage_id                :bigint           not null
#
# Indexes
#
#  idx_jabvox_tasks_account_deleted_at                 (account_id,deleted_at_jabvox)
#  index_jabvox_tasks_on_account_and_recurrence        (account_id,recurrence_unit_jabvox) WHERE (recurrence_unit_jabvox IS NOT NULL)
#  index_jabvox_tasks_on_account_id                    (account_id)
#  index_jabvox_tasks_on_account_id_and_board_id       (account_id,board_id)
#  index_jabvox_tasks_on_account_id_and_contact_id     (account_id,contact_id)
#  index_jabvox_tasks_on_account_id_and_due_at_jabvox  (account_id,due_at_jabvox)
#  index_jabvox_tasks_on_assignee_id                   (assignee_id)
#  index_jabvox_tasks_on_board_id                      (board_id)
#  index_jabvox_tasks_on_created_by_id                 (created_by_id)
#  index_jabvox_tasks_on_recurrence_parent_id          (recurrence_parent_id)
#  index_jabvox_tasks_on_source_task_id                (source_task_id)
#  index_jabvox_tasks_on_stage_id                      (stage_id)
#  index_jabvox_tasks_on_stage_id_and_position_jabvox  (stage_id,position_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (board_id => jabvox_task_boards.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (recurrence_parent_id => jabvox_tasks.id) ON DELETE => nullify
#  fk_rails_...  (source_task_id => jabvox_tasks.id) ON DELETE => nullify
#  fk_rails_...  (stage_id => jabvox_task_stages.id)
#
class JabvoxTask < ApplicationRecord
  self.table_name = 'jabvox_tasks'

  PRIORITIES = %w[low normal high urgent].freeze
  STATUSES = %w[open done].freeze

  belongs_to :account
  belongs_to :board, class_name: 'JabvoxTaskBoard'
  belongs_to :stage, class_name: 'JabvoxTaskStage'
  # `contact` sustituye a `jabvox_lead`. La asociación vieja sigue mientras queden filas
  # antiguas apuntando por lead.
  belongs_to :contact, optional: true
  # Legacy single-assignee column, kept as the "primary assignee" mirror of #assignees.first.
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  # Multiple users can be responsible for a task.
  has_many :task_assignees, class_name: 'JabvoxTaskAssignee', foreign_key: :task_id,
                            inverse_of: :task, dependent: :destroy
  has_many :assignees, through: :task_assignees, source: :user

  # Append-only activity/history log for this task.
  has_many :activities, -> { order(created_at: :asc) }, class_name: 'JabvoxTaskActivity',
                                                        foreign_key: :task_id, inverse_of: :task,
                                                        dependent: :delete_all

  # Calendar events created from this task's due date(s); removed with the task.
  has_many :calendar_events, class_name: 'JabvoxCalendarEvent',
                             dependent: :destroy, inverse_of: :jabvox_task

  # Recurring per-task automations (send email/sms/message every N days/weeks/months) and
  # their dispatch log.
  has_many :automations, class_name: 'JabvoxTaskAutomation', foreign_key: :task_id,
                         inverse_of: :task, dependent: :destroy
  has_many :automation_runs, -> { order(run_at_jabvox: :desc) },
           class_name: 'JabvoxTaskAutomationRun', foreign_key: :task_id,
           inverse_of: :task, dependent: :delete_all

  validates :title_jabvox, presence: true
  validates :priority_jabvox, inclusion: { in: PRIORITIES }
  validates :status_jabvox, inclusion: { in: STATUSES }
  # El tablero, la columna y el contacto tienen que ser de la misma cuenta que la tarea.
  # Sin esto, `board_id`/`stage_id`/`contact_id` viajan en el formulario y se podía crear
  # una tarea apuntando al tablero de OTRA cuenta: aterrizaba en su columna, disparaba sus
  # automatizaciones y devolvía el nombre de su contacto en la respuesta.
  #
  # Va en el modelo y no en el controlador para que valga venga de donde venga el guardado
  # (API, consola, importación). Es el mismo criterio que ya usaba `sync_assignees!`.
  validate :associations_belong_to_account

  scope :ordered, -> { order(:position_jabvox, :created_at) }
  scope :active, -> { where(deleted_at_jabvox: nil) }
  scope :trashed, -> { where.not(deleted_at_jabvox: nil) }
  scope :with_due_date, -> { where.not(due_at_jabvox: nil) }

  # Al crear, la tarjeta se coloca al final de su columna en vez de quedar en la posición 0
  # por defecto. Sin esto, todas las tareas de una columna nacían con `position_jabvox = 0`
  # y el orden dentro de la columna lo decidía solo el desempate por `created_at`, que el
  # frontend no replicaba: se percibía como un orden aleatorio que bailaba entre recargas.
  #
  # Va en el modelo y no en el controlador para que valga venga de donde venga el alta
  # (API, consola, importación, recurrencia), igual que `associations_belong_to_account`.
  before_validation :set_default_position, on: :create

  # Columns whose change should re-sync the task's calendar events.
  CALENDAR_RELEVANT = %w[due_at_jabvox due_dates_jabvox title_jabvox description_jabvox
                         status_jabvox contact_id assignee_id deleted_at_jabvox].freeze

  # Fire stage automations when the card lands in a (new) stage — on create and whenever
  # stage_id changes — mirroring the kanban conversation-stage hook.
  after_commit :fire_stage_automations, on: :create
  after_commit :fire_stage_automations_on_move, on: :update
  after_commit :sync_calendar, on: %i[create update]
  # When a done task is reopened, reschedule its recurring automations so they
  # resume from now instead of firing every run missed while it was completed.
  after_commit :reschedule_automations_on_reopen, on: :update
  # Una tarea recurrente engendra la siguiente al completarse. Va aquí y no en el
  # controlador para que valga igual si se cierra desde la ficha, moviéndola a la columna
  # de completadas o desde una automatización.
  # Completar una tarea la lleva a la columna marcada como completada, y reabrirla la
  # devuelve a la inicial: el estado y la columna cuentan lo mismo, así que moverse a mano
  # después de marcar "hecho" sobra. Va antes de crear la repetición para que el historial
  # quede en orden.
  after_commit :move_to_role_stage, on: :update, if: :saved_change_to_status_jabvox?
  # Y el camino inverso: arrastrar la tarjeta a la columna de completadas la cierra, y
  # sacarla de ahí la reabre. Sin esto quedaba en la columna de terminadas pero contando
  # como pendiente, y el barrido de vencidas podía mandarla a inactiva.
  after_commit :sync_status_from_stage, on: :update, if: :saved_change_to_stage_id?
  after_commit :create_next_occurrence, on: :update, if: :just_completed?

  # Replace the task's assignees with the given user ids (scoped to this account's users).
  # Keeps the legacy assignee_id in sync with the first id (the "primary assignee").
  # Returns [added_user_ids, removed_user_ids] so the caller can log activity.
  def sync_assignees!(user_ids)
    desired = Array(user_ids).map(&:to_i).uniq
    desired &= account.users.pluck(:id) if desired.any?

    current = task_assignees.pluck(:user_id)
    added = desired - current
    removed = current - desired

    apply_assignee_changes(desired, added, removed)

    added.each do |user_id|
      user = account.users.find_by(id: user_id)
      next unless user

      Jabvox::ModuleNotificationService.create!(
        account: account,
        user: user,
        type: :jabvox_task_assigned,
        actor: self,
        title: 'Tarea asignada',
        body: title_jabvox,
        path: "/app/accounts/#{account_id}/jabvox/tasks/view/#{id}"
      )
    end

    # Copiar al tablero personal de los responsables nuevos, si el tablero de origen lo
    # tiene activado. Fuera de la transacción: que falle una copia no debe deshacer la
    # asignación en sí.
    copy_to_assignee_boards if added.any?

    [added, removed]
  end

  # Record one entry in the append-only activity log. `user` is who performed the change.
  def log_activity(action, user, metadata = {})
    activities.create!(
      account_id: account_id,
      user_id: user&.id,
      action_jabvox: action.to_s,
      metadata_jabvox: metadata
    )
  end

  # Lo que viaja al frontend cuando la tarea es el actor de una notificación (el
  # recordatorio de vencimiento). Notification lo exige de todo primary_actor.
  def push_event_data
    {
      id: id,
      title: title_jabvox,
      status: status_jabvox,
      board_id: board_id,
      due_at: due_at_jabvox
    }
  end

  # Se repite: tiene unidad de recurrencia configurada.
  def recurring?
    Jabvox::TaskRecurrenceService::UNITS.include?(recurrence_unit_jabvox.to_s)
  end

  # Mueve la tarjeta a `target_stage` en la posición `target_position` y recompacta las
  # posiciones (origen y destino) a 0..n-1 en una transacción. Así arrastrar una tarjeta
  # dentro de la misma columna o entre columnas deja un orden consistente, sin huecos ni
  # empates. El cambio de `stage_id` dispara las automatizaciones de la etapa destino por
  # el after_commit del modelo, como cualquier otro movimiento.
  def reorder_within_stage!(target_stage, target_position)
    transaction do
      source_stage_id = stage_id
      update!(stage_id: target_stage.id)
      siblings = account.jabvox_tasks
                        .where(stage_id: target_stage.id)
                        .where.not(id: id)
                        .order(:position_jabvox, :created_at)
                        .pluck(:id)
      pos = target_position.to_i.clamp(0, siblings.length)
      ordered_ids = siblings.insert(pos, id)
      resequence_positions!(target_stage.id, ordered_ids)
      # Si cambió de columna, la de origen queda con un hueco: se recompacta también para
      # que ambas queden 0..n-1 sin huecos.
      resequence_stage!(source_stage_id) if source_stage_id != target_stage.id
    end
    self
  end

  private

  # Recompacta las posiciones de una columna a 0..n-1 en su orden actual.
  def resequence_stage!(stage_id)
    scope = account.jabvox_tasks.where(stage_id: stage_id).order(:position_jabvox, :created_at)
    resequence_positions!(stage_id, scope.pluck(:id))
  end

  # update_all a propósito: solo reescribe `position_jabvox`, sin reentrar en los callbacks
  # de la tarea (dispararían automatizaciones y sync de calendario por un reordenamiento).
  def resequence_positions!(stage_id, ordered_ids)
    ordered_ids.each_with_index do |task_id, index|
      # rubocop:disable Rails/SkipsModelValidations
      account.jabvox_tasks.where(id: task_id, stage_id: stage_id)
             .update_all(position_jabvox: index)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # Posición por defecto = final de la columna (max + 1). Solo cuando no se envió una
  # posición explícita (el default de la columna es 0), para no pisar un alta que ya trae
  # su posición.
  def set_default_position
    return if position_jabvox.present? && position_jabvox.positive?
    return if stage_id.blank? || account_id.blank?

    max = account.jabvox_tasks.where(stage_id: stage_id).maximum(:position_jabvox)
    self.position_jabvox = max.nil? ? 0 : max + 1
  end

  # Se compara contra account_id en vez de cargar la cuenta: una consulta por asociación
  # y solo de las que vienen informadas.
  def associations_belong_to_account
    return if account_id.blank?

    { board: board, stage: stage, contact: contact }.each do |name, record|
      next if record.nil? || record.account_id == account_id

      errors.add(name, :invalid, message: 'no pertenece a esta cuenta')
    end
  end

  def just_completed?
    saved_change_to_status_jabvox? && status_jabvox == 'done'
  end

  # Mueve la tarea a la columna que corresponde a su nuevo estado, si el tablero la marcó.
  # Un tablero sin columna marcada no se toca: mover a una cualquiera sería peor que no
  # mover. Tampoco se toca si ya está donde debe.
  def move_to_role_stage
    role = status_jabvox == 'done' ? 'done' : 'initial'
    target = role == 'done' ? board.done_stage : board.initial_stage
    return if target.nil? || stage_id == target.id

    from = stage
    update_column(:stage_id, target.id) # rubocop:disable Rails/SkipsModelValidations
    log_activity(:stage_changed, nil, from: from&.name_jabvox, to: target.name_jabvox,
                                      reason: "status_#{status_jabvox}")
  rescue StandardError => e
    Rails.logger.error "[JabvoxTask##{id}] no se pudo mover a la columna de #{role}: #{e.message}"
  end

  # Arrastrar la tarjeta también cambia el estado, para que columna y estado no se
  # contradigan. Solo actúa sobre la columna marcada como completada: las intermedias no
  # dicen nada del estado.
  def sync_status_from_stage
    done_id = board.done_stage&.id
    return if done_id.nil?

    entered_done = stage_id == done_id
    # Entrar en la columna de completadas cierra; salir de ella reabre. Un movimiento
    # entre columnas intermedias no dice nada del estado y se deja como está.
    return if entered_done == (status_jabvox == 'done')

    apply_status_from_stage(entered_done ? 'done' : 'open')
  rescue StandardError => e
    Rails.logger.error "[JabvoxTask##{id}] no se pudo sincronizar el estado: #{e.message}"
  end

  def apply_status_from_stage(desired)
    update_column(:status_jabvox, desired) # rubocop:disable Rails/SkipsModelValidations
    log_activity(:status_changed, nil, to: desired, reason: 'stage_moved')
  end

  # Si la copia falla no debe tumbar el guardado de la tarea que sí se completó: se
  # registra y se sigue. Perder una repetición es molesto; perder el cierre, peor.
  def create_next_occurrence
    Jabvox::TaskRecurrenceService.new(self).create_next
  rescue StandardError => e
    Rails.logger.error "[JabvoxTask##{id}] no se pudo crear la siguiente ocurrencia: #{e.message}"
  end

  def fire_stage_automations_on_move
    return unless saved_change_to_stage_id?

    fire_stage_automations
  end

  # On reopen (done -> open), push any past-due next_run_at forward so reopening
  # doesn't immediately fire every recurrence skipped while the task was done.
  def reschedule_automations_on_reopen
    return unless saved_change_to_status_jabvox?

    from, to = saved_change_to_status_jabvox
    return unless from == 'done' && to != 'done'

    now = Time.current
    # Solo se corre la fecha del próximo disparo: no hay nada que validar y se evita
    # reentrar en los callbacks de la automatización.
    # rubocop:disable Rails/SkipsModelValidations
    automations.where(active_jabvox: true)
               .where(next_run_at_jabvox: ..now)
               .find_each { |a| a.update_column(:next_run_at_jabvox, now + a.interval_duration) }
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Alta/baja de responsables y espejo del principal, en una sola transacción.
  def apply_assignee_changes(desired, added, removed)
    transaction do
      task_assignees.where(user_id: removed).delete_all if removed.any?
      added.each { |uid| task_assignees.create!(user_id: uid, account_id: account_id) }
      new_primary = desired.first
      next if assignee_id == new_primary

      # update_column a propósito: assignee_id es solo el espejo de assignees.first, y
      # pasar por validaciones aquí volvería a disparar los callbacks de la tarea.
      # rubocop:disable Rails/SkipsModelValidations
      update_column(:assignee_id, new_primary)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def fire_stage_automations
    Jabvox::TaskAutomationJob.perform_later(id)
  end

  # Una copia fallida no puede tumbar la asignación: se registra y se sigue.
  def copy_to_assignee_boards
    Jabvox::TaskAssigneeBoardCopyService.new(reload).perform
  rescue StandardError => e
    Rails.logger.error("[jabvox] copia a tablero de responsable falló task=#{id}: #{e.class}")
  end

  # Re-sync calendar events whenever a calendar-relevant field changed (or on create).
  def sync_calendar
    return if previously_new_record? && due_at_jabvox.blank? && Array(due_dates_jabvox).blank?
    return unless previously_new_record? || saved_changes.keys.intersect?(CALENDAR_RELEVANT)

    Jabvox::TaskCalendarSyncJob.perform_later(id)
  end
end
