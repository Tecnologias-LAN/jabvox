# Append-only audit trail of outbound task webhooks: which URL, the result, and why it was
# blocked (e.g. SSRF guard rejected a private/internal address).
# == Schema Information
#
# Table name: jabvox_task_webhook_deliveries
#
#  id                   :bigint           not null, primary key
#  error_jabvox         :text
#  payload_jabvox       :jsonb            not null
#  response_code_jabvox :integer
#  status_jabvox        :string           default("pending"), not null
#  url_jabvox           :string           not null
#  created_at           :datetime         not null
#  account_id           :bigint           not null
#  automation_id        :bigint
#  task_id              :bigint
#
# Indexes
#
#  idx_on_account_id_created_at_5aabb85ef6                (account_id,created_at)
#  index_jabvox_task_webhook_deliveries_on_account_id     (account_id)
#  index_jabvox_task_webhook_deliveries_on_automation_id  (automation_id)
#  index_jabvox_task_webhook_deliveries_on_task_id        (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (automation_id => jabvox_task_stage_automations.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#
class JabvoxTaskWebhookDelivery < ApplicationRecord
  self.table_name = 'jabvox_task_webhook_deliveries'

  self.record_timestamps = false

  STATUSES = %w[pending delivered failed blocked].freeze

  belongs_to :account
  belongs_to :task, class_name: 'JabvoxTask', optional: true
  belongs_to :automation, class_name: 'JabvoxTaskStageAutomation', optional: true

  validates :url_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  before_validation :stamp_created_at, on: :create

  scope :recent, -> { order(created_at: :desc) }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
