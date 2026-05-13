# == Schema Information
#
# Table name: jabvox_kanban_stage_automations
#
#  id                       :bigint           not null, primary key
#  active                   :boolean          default(TRUE), not null
#  automation_type          :string           default("send_message"), not null
#  channel_type             :string
#  message_body             :text
#  name                     :string           not null
#  trigger_hours            :integer
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  inbox_id                 :bigint
#  jabvox_email_template_id :bigint
#  jabvox_kanban_stage_id   :bigint           not null
#  jabvox_sms_provider_id   :bigint
#  target_stage_id          :bigint
#
# Indexes
#
#  index_jabvox_kanban_stage_automations_on_account_id              (account_id)
#  index_jabvox_kanban_stage_automations_on_inbox_id                (inbox_id)
#  index_jabvox_kanban_stage_automations_on_jabvox_kanban_stage_id  (jabvox_kanban_stage_id)
#  index_jabvox_stage_automations_on_target_stage                   (target_stage_id)
#
# Foreign Keys
#
#  fk_jabvox_stage_automations_target_stage  (target_stage_id => jabvox_kanban_stages.id)
#  fk_rails_...                              (account_id => accounts.id)
#  fk_rails_...                              (inbox_id => inboxes.id)
#  fk_rails_...                              (jabvox_email_template_id => jabvox_email_templates.id)
#  fk_rails_...                              (jabvox_kanban_stage_id => jabvox_kanban_stages.id)
#  fk_rails_...                              (jabvox_sms_provider_id => jabvox_sms_providers.id)
#
class JabvoxKanbanStageAutomation < ApplicationRecord
  AUTOMATION_TYPES = %w[send_message move_after_hours move_if_inactive].freeze
  CHANNEL_TYPES = %w[inbox email sms].freeze

  belongs_to :account
  belongs_to :jabvox_kanban_stage
  belongs_to :target_stage, class_name: 'JabvoxKanbanStage', optional: true
  belongs_to :inbox, optional: true
  belongs_to :jabvox_email_template, optional: true
  belongs_to :jabvox_sms_provider, optional: true

  validates :name, presence: true
  validates :automation_type, inclusion: { in: AUTOMATION_TYPES }
  validates :channel_type, inclusion: { in: CHANNEL_TYPES }, if: :send_message?
  validates :trigger_hours,
            numericality: { only_integer: true, greater_than: 0 },
            if: :movement_type?
  validates :target_stage_id, presence: true, if: :movement_type?
  validate :channel_references_valid, if: :send_message?

  scope :active, -> { where(active: true) }

  def send_message?
    automation_type == 'send_message'
  end

  def movement_type?
    %w[move_after_hours move_if_inactive].include?(automation_type)
  end

  private

  def channel_references_valid
    case channel_type
    when 'inbox'
      errors.add(:inbox, 'must be present for inbox channel') if inbox_id.blank?
    when 'email'
      errors.add(:jabvox_email_template, 'must be present for email channel') if jabvox_email_template_id.blank?
    when 'sms'
      errors.add(:jabvox_sms_provider, 'must be present for sms channel') if jabvox_sms_provider_id.blank?
      errors.add(:message_body, "can't be blank for sms channel") if message_body.blank?
    end
  end
end
