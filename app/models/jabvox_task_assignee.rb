# Join between a task and a user responsible for it. A task can have many assignees.
# The legacy JabvoxTask#assignee_id mirrors the first of these (the "primary assignee").
# == Schema Information
#
# Table name: jabvox_task_assignees
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  task_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_task_assignees_on_account_id     (account_id)
#  index_jabvox_task_assignees_on_task_and_user  (task_id,user_id) UNIQUE
#  index_jabvox_task_assignees_on_task_id        (task_id)
#  index_jabvox_task_assignees_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxTaskAssignee < ApplicationRecord
  self.table_name = 'jabvox_task_assignees'

  belongs_to :task, class_name: 'JabvoxTask'
  belongs_to :user
  belongs_to :account

  validates :user_id, uniqueness: { scope: :task_id }
end
