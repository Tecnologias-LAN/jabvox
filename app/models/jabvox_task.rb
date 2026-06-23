# A task card on a board. Optionally references a lead (read-only) and an optional due date
# (used by the calendar view). Moving the card to a new stage fires that stage's automations.
# == Schema Information
#
# Table name: jabvox_tasks
#
#  id                 :bigint           not null, primary key
#  description_jabvox :text
#  due_at_jabvox      :datetime
#  due_dates_jabvox   :jsonb            not null
#  position_jabvox    :integer          default(0), not null
#  priority_jabvox    :string           default("normal"), not null
#  status_jabvox      :string           default("open"), not null
#  title_jabvox       :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assignee_id        :bigint
#  board_id           :bigint           not null
#  created_by_id      :bigint
#  jabvox_lead_id     :bigint
#  stage_id           :bigint           not null
#
# Indexes
#
#  index_jabvox_tasks_on_account_id                     (account_id)
#  index_jabvox_tasks_on_account_id_and_board_id        (account_id,board_id)
#  index_jabvox_tasks_on_account_id_and_due_at_jabvox   (account_id,due_at_jabvox)
#  index_jabvox_tasks_on_account_id_and_jabvox_lead_id  (account_id,jabvox_lead_id)
#  index_jabvox_tasks_on_assignee_id                    (assignee_id)
#  index_jabvox_tasks_on_board_id                       (board_id)
#  index_jabvox_tasks_on_created_by_id                  (created_by_id)
#  index_jabvox_tasks_on_jabvox_lead_id                 (jabvox_lead_id)
#  index_jabvox_tasks_on_stage_id                       (stage_id)
#  index_jabvox_tasks_on_stage_id_and_position_jabvox   (stage_id,position_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (board_id => jabvox_task_boards.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id)
#  fk_rails_...  (stage_id => jabvox_task_stages.id)
#
class JabvoxTask < ApplicationRecord
  self.table_name = 'jabvox_tasks'

  PRIORITIES = %w[low normal high urgent].freeze
  STATUSES = %w[open done].freeze

  belongs_to :account
  belongs_to :board, class_name: 'JabvoxTaskBoard'
  belongs_to :stage, class_name: 'JabvoxTaskStage'
  belongs_to :jabvox_lead, class_name: 'JabvoxLead', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  # Calendar events created from this task's due date(s); removed with the task.
  has_many :calendar_events, class_name: 'JabvoxCalendarEvent',
                             dependent: :destroy, inverse_of: :jabvox_task

  validates :title_jabvox, presence: true
  validates :priority_jabvox, inclusion: { in: PRIORITIES }
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position_jabvox, :created_at) }
  scope :with_due_date, -> { where.not(due_at_jabvox: nil) }

  # Columns whose change should re-sync the task's calendar events.
  CALENDAR_RELEVANT = %w[due_at_jabvox due_dates_jabvox title_jabvox description_jabvox
                         status_jabvox jabvox_lead_id assignee_id].freeze

  # Fire stage automations when the card lands in a (new) stage — on create and whenever
  # stage_id changes — mirroring the kanban conversation-stage hook.
  after_commit :fire_stage_automations, on: :create
  after_commit :fire_stage_automations_on_move, on: :update
  after_commit :sync_calendar, on: %i[create update]

  private

  def fire_stage_automations_on_move
    return unless saved_change_to_stage_id?

    fire_stage_automations
  end

  def fire_stage_automations
    Jabvox::TaskAutomationJob.perform_later(id)
  end

  # Re-sync calendar events whenever a calendar-relevant field changed (or on create).
  def sync_calendar
    return if previously_new_record? && due_at_jabvox.blank? && Array(due_dates_jabvox).blank?
    return unless previously_new_record? || saved_changes.keys.intersect?(CALENDAR_RELEVANT)

    Jabvox::TaskCalendarSyncJob.perform_later(id)
  end
end
