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
#  trigger_unit_jabvox      :string
#  trigger_value_jabvox     :integer
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  created_by_id            :bigint
#  inbox_id                 :bigint
#  jabvox_email_template_id :bigint
#  jabvox_kanban_stage_id   :bigint           not null
#  jabvox_sms_provider_id   :bigint
#  target_stage_id          :bigint
#
# Indexes
#
#  index_jabvox_kanban_stage_automations_on_account_id              (account_id)
#  index_jabvox_kanban_stage_automations_on_created_by_id           (created_by_id)
#  index_jabvox_kanban_stage_automations_on_inbox_id                (inbox_id)
#  index_jabvox_kanban_stage_automations_on_jabvox_kanban_stage_id  (jabvox_kanban_stage_id)
#  index_jabvox_stage_automations_on_target_stage                   (target_stage_id)
#
# Foreign Keys
#
#  fk_jabvox_stage_automations_target_stage  (target_stage_id => jabvox_kanban_stages.id)
#  fk_rails_...                              (account_id => accounts.id)
#  fk_rails_...                              (created_by_id => users.id)
#  fk_rails_...                              (inbox_id => inboxes.id)
#  fk_rails_...                              (jabvox_email_template_id => jabvox_email_templates.id)
#  fk_rails_...                              (jabvox_kanban_stage_id => jabvox_kanban_stages.id)
#  fk_rails_...                              (jabvox_sms_provider_id => jabvox_sms_providers.id)
#
class JabvoxKanbanStageAutomation < ApplicationRecord
  AUTOMATION_TYPES = %w[
    send_message move_after_hours move_if_inactive
    move_if_no_incoming move_if_no_outgoing
  ].freeze
  CHANNEL_TYPES = %w[inbox email sms].freeze
  # El disparo por tiempo se mide en minutos u horas, a elección del usuario: "escalar si
  # nadie contesta en 30 minutos" y "mover tras 48 horas" son casos igual de reales.
  TRIGGER_UNITS = %w[minutes hours].freeze

  belongs_to :account
  belongs_to :jabvox_kanban_stage
  belongs_to :target_stage, class_name: 'JabvoxKanbanStage', optional: true
  belongs_to :inbox, optional: true
  belongs_to :jabvox_email_template, optional: true
  belongs_to :jabvox_sms_provider, optional: true

  validates :name, presence: true
  validates :automation_type, inclusion: { in: AUTOMATION_TYPES }
  validates :channel_type, inclusion: { in: CHANNEL_TYPES }, if: :send_message?
  validates :trigger_value_jabvox,
            numericality: { only_integer: true, greater_than: 0 },
            if: :movement_type?
  validates :trigger_unit_jabvox, inclusion: { in: TRIGGER_UNITS }, if: :movement_type?
  validates :target_stage_id, presence: true, if: :movement_type?
  validate :channel_references_valid, if: :send_message?

  scope :active, -> { where(active: true) }

  def send_message?
    automation_type == 'send_message'
  end

  def movement_type?
    %w[move_after_hours move_if_inactive move_if_no_incoming move_if_no_outgoing].include?(automation_type)
  end

  # Momento a partir del cual la tarjeta se considera "vencida". Las automatizaciones creadas
  # antes de existir la unidad solo tienen `trigger_hours`, así que se leen como horas.
  def trigger_cutoff
    value = trigger_value_jabvox || trigger_hours
    return nil if value.blank?

    unit = trigger_unit_jabvox.presence || 'hours'
    unit == 'minutes' ? value.minutes.ago : value.hours.ago
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
