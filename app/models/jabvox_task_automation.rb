# A recurring automation attached to a single task: every N days/weeks/months it sends an
# email / sms / inbox message to some combination of the lead, the task assignees, the lead's
# captured contacts, and/or a manual address. A daily scheduled job picks up rows whose
# next_run_at has passed and dispatches them via Jabvox::TaskAutomationDispatchService.
# == Schema Information
#
# Table name: jabvox_task_automations
#
#  id                    :bigint           not null, primary key
#  active_jabvox         :boolean          default(TRUE), not null
#  body_jabvox           :text
#  channel_jabvox        :string           not null
#  end_at_jabvox         :datetime
#  interval_count_jabvox :integer          default(1), not null
#  interval_unit_jabvox  :string           default("day"), not null
#  last_run_at_jabvox    :datetime
#  manual_email_jabvox   :string           default(""), not null
#  manual_phone_jabvox   :string           default(""), not null
#  name_jabvox           :string           default(""), not null
#  next_run_at_jabvox    :datetime
#  recipients_jabvox     :string           default("lead"), not null
#  runs_count_jabvox     :integer          default(0), not null
#  start_at_jabvox       :datetime
#  subject_jabvox        :string           default(""), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  created_by_id         :bigint
#  email_template_id     :bigint
#  inbox_id              :bigint
#  sms_provider_id       :bigint
#  task_id               :bigint           not null
#
# Indexes
#
#  idx_on_active_jabvox_next_run_at_jabvox_c67e09e205       (active_jabvox,next_run_at_jabvox)
#  index_jabvox_task_automations_on_account_id              (account_id)
#  index_jabvox_task_automations_on_account_id_and_task_id  (account_id,task_id)
#  index_jabvox_task_automations_on_created_by_id           (created_by_id)
#  index_jabvox_task_automations_on_email_template_id       (email_template_id)
#  index_jabvox_task_automations_on_inbox_id                (inbox_id)
#  index_jabvox_task_automations_on_sms_provider_id         (sms_provider_id)
#  index_jabvox_task_automations_on_task_id                 (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (email_template_id => jabvox_email_templates.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sms_provider_id => jabvox_sms_providers.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#
class JabvoxTaskAutomation < ApplicationRecord
  include Jabvox::AccountScopedReferences

  self.table_name = 'jabvox_task_automations'

  CHANNELS = %w[email sms inbox].freeze
  UNITS = %w[day week month].freeze
  RECIPIENT_KINDS = %w[lead assignees lead_contacts manual].freeze

  belongs_to :account
  belongs_to :task, class_name: 'JabvoxTask'
  belongs_to :email_template, class_name: 'JabvoxEmailTemplate', optional: true
  belongs_to :inbox, optional: true
  belongs_to :sms_provider, class_name: 'JabvoxSmsProvider', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :runs, -> { order(run_at_jabvox: :desc) }, class_name: 'JabvoxTaskAutomationRun',
                                                      foreign_key: :automation_id,
                                                      inverse_of: :automation, dependent: :destroy

  # Misma razón que en las automatizaciones de etapa: las FKs salientes viajan en el
  # formulario y hay que comprobar que son de esta cuenta.
  validates_account_scope :inbox, :email_template, :sms_provider

  validates :channel_jabvox, inclusion: { in: CHANNELS }
  validates :interval_unit_jabvox, inclusion: { in: UNITS }
  validates :interval_count_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 365 }

  # Due automations exclude tasks that are already done: completing a task stops
  # its recurring automations from firing (without deactivating them, so they
  # resume if the task is reopened).
  scope :due, lambda { |now = Time.current|
    joins(:task)
      .where(active_jabvox: true)
      .where(next_run_at_jabvox: ..now)
      .where.not(jabvox_tasks: { status_jabvox: 'done' })
  }

  before_validation :set_initial_schedule, on: :create

  # Parsed recipient kinds (e.g. ["lead", "assignees"]).
  def recipient_kinds
    recipients_jabvox.to_s.split(',').map(&:strip).reject(&:blank?) & RECIPIENT_KINDS
  end

  # Step length for one recurrence as an ActiveSupport::Duration.
  def interval_duration
    count = interval_count_jabvox.to_i
    case interval_unit_jabvox
    when 'week' then count.weeks
    when 'month' then count.months
    else count.days
    end
  end

  # Advance the schedule after a dispatch: bump counters and compute the next run, deactivating
  # if we've passed end_at.
  def mark_ran!(now = Time.current)
    next_run = (next_run_at_jabvox || now) + interval_duration
    finished = end_at_jabvox.present? && next_run > end_at_jabvox
    update!(
      last_run_at_jabvox: now,
      runs_count_jabvox: runs_count_jabvox + 1,
      next_run_at_jabvox: finished ? nil : next_run,
      active_jabvox: finished ? false : active_jabvox
    )
  end

  private

  def set_initial_schedule
    self.start_at_jabvox ||= Time.current
    self.next_run_at_jabvox ||= start_at_jabvox
  end
end
