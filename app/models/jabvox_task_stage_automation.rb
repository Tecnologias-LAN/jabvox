# An automation fired when a task enters a stage: send a message to the lead's contact
# (inbox/email/sms), POST a signed + SSRF-checked webhook, or move the card after
# time/inactivity. Mirrors JabvoxKanbanStageAutomation.
# == Schema Information
#
# Table name: jabvox_task_stage_automations
#
#  id                     :bigint           not null, primary key
#  active_jabvox          :boolean          default(TRUE), not null
#  automation_type_jabvox :string           not null
#  channel_type_jabvox    :string
#  message_body_jabvox    :text
#  trigger_hours_jabvox   :integer
#  webhook_secret_jabvox  :text
#  webhook_url_jabvox     :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  email_template_id      :bigint
#  inbox_id               :bigint
#  sms_provider_id        :bigint
#  stage_id               :bigint           not null
#  target_stage_id        :bigint
#
# Indexes
#
#  index_jabvox_task_stage_automations_on_account_id               (account_id)
#  index_jabvox_task_stage_automations_on_account_id_and_stage_id  (account_id,stage_id)
#  index_jabvox_task_stage_automations_on_email_template_id        (email_template_id)
#  index_jabvox_task_stage_automations_on_inbox_id                 (inbox_id)
#  index_jabvox_task_stage_automations_on_sms_provider_id          (sms_provider_id)
#  index_jabvox_task_stage_automations_on_stage_id                 (stage_id)
#  index_jabvox_task_stage_automations_on_target_stage_id          (target_stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (email_template_id => jabvox_email_templates.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sms_provider_id => jabvox_sms_providers.id)
#  fk_rails_...  (stage_id => jabvox_task_stages.id)
#  fk_rails_...  (target_stage_id => jabvox_task_stages.id)
#
class JabvoxTaskStageAutomation < ApplicationRecord
  self.table_name = 'jabvox_task_stage_automations'

  AUTOMATION_TYPES = %w[send_message webhook move_after_hours move_if_inactive].freeze
  CHANNEL_TYPES = %w[inbox email sms].freeze

  belongs_to :account
  belongs_to :stage, class_name: 'JabvoxTaskStage'
  belongs_to :inbox, optional: true
  belongs_to :email_template, class_name: 'JabvoxEmailTemplate', optional: true
  belongs_to :sms_provider, class_name: 'JabvoxSmsProvider', optional: true
  belongs_to :target_stage, class_name: 'JabvoxTaskStage', optional: true

  encrypts :webhook_secret_jabvox if Jabvox.encryption_configured?

  validates :automation_type_jabvox, inclusion: { in: AUTOMATION_TYPES }
  validates :channel_type_jabvox, inclusion: { in: CHANNEL_TYPES }, allow_nil: true
  validates :channel_type_jabvox, presence: true, if: :send_message?
  validates :webhook_url_jabvox, presence: true, if: :webhook?
  validates :trigger_hours_jabvox, presence: true, if: :time_based?
  validates :target_stage_id, presence: true, if: :time_based?

  scope :active, -> { where(active_jabvox: true) }

  def send_message?
    automation_type_jabvox == 'send_message'
  end

  def webhook?
    automation_type_jabvox == 'webhook'
  end

  def time_based?
    %w[move_after_hours move_if_inactive].include?(automation_type_jabvox)
  end
end
