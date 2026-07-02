# One dispatch attempt of a task automation. Surfaced in the task detail view and summarized
# as badges on the board/calendar so users can see what was sent and when.
# == Schema Information
#
# Table name: jabvox_task_automation_runs
#
#  id                      :bigint           not null, primary key
#  channel_jabvox          :string           not null
#  detail_jabvox           :text
#  recipients_count_jabvox :integer          default(0), not null
#  run_at_jabvox           :datetime         not null
#  status_jabvox           :string           default("sent"), not null
#  account_id              :bigint           not null
#  automation_id           :bigint
#  task_id                 :bigint           not null
#
# Indexes
#
#  idx_on_account_id_task_id_run_at_jabvox_83a99062cf  (account_id,task_id,run_at_jabvox)
#  index_jabvox_task_automation_runs_on_account_id     (account_id)
#  index_jabvox_task_automation_runs_on_automation_id  (automation_id)
#  index_jabvox_task_automation_runs_on_task_id        (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (automation_id => jabvox_task_automations.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#
class JabvoxTaskAutomationRun < ApplicationRecord
  self.table_name = 'jabvox_task_automation_runs'

  STATUSES = %w[sent partial failed skipped].freeze

  belongs_to :account
  belongs_to :task, class_name: 'JabvoxTask'
  belongs_to :automation, class_name: 'JabvoxTaskAutomation', optional: true

  validates :channel_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
end
