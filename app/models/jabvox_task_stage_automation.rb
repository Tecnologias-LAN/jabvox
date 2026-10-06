# An automation fired when a task enters a stage: send a message to the lead's contact
# (inbox/email/sms), POST a signed + SSRF-checked webhook, or move the card after
# time/inactivity. Mirrors JabvoxKanbanStageAutomation.
# == Schema Information
#
# Table name: jabvox_task_stage_automations
#
#  id                       :bigint           not null, primary key
#  active_jabvox            :boolean          default(TRUE), not null
#  automation_type_jabvox   :string           not null
#  channel_type_jabvox      :string
#  message_body_jabvox      :text
#  template_language_jabvox :string
#  template_name_jabvox     :string
#  template_params_jabvox   :jsonb            not null
#  trigger_hours_jabvox     :integer
#  trigger_unit_jabvox      :string
#  trigger_value_jabvox     :integer
#  webhook_secret_jabvox    :text
#  webhook_url_jabvox       :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  email_template_id        :bigint
#  inbox_id                 :bigint
#  sms_provider_id          :bigint
#  stage_id                 :bigint           not null
#  target_stage_id          :bigint
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
  include Jabvox::AccountScopedReferences

  self.table_name = 'jabvox_task_stage_automations'

  AUTOMATION_TYPES = %w[send_message webhook move_after_hours move_if_inactive].freeze
  # `inbox` enviaba texto libre, que WhatsApp solo acepta dentro de la ventana de 24h. Una
  # automatización de tiempo dispara justamente cuando la tarea lleva rato quieta, o sea
  # fuera de esa ventana: por eso el envío es por plantilla aprobada.
  CHANNEL_TYPES = %w[whatsapp_template email sms].freeze
  # El disparo se mide en minutos u horas, como en Kanban: "avisar 30 minutos antes" y
  # "mover tras 48 horas sin tocar" son casos igual de reales.
  TRIGGER_UNITS = %w[minutes hours].freeze

  belongs_to :account
  belongs_to :stage, class_name: 'JabvoxTaskStage'
  belongs_to :inbox, optional: true
  belongs_to :email_template, class_name: 'JabvoxEmailTemplate', optional: true
  belongs_to :sms_provider, class_name: 'JabvoxSmsProvider', optional: true
  belongs_to :target_stage, class_name: 'JabvoxTaskStage', optional: true
  # Webhook delivery logs are removed with the automation so deletion doesn't
  # fail on their FK.
  has_many :webhook_deliveries, class_name: 'JabvoxTaskWebhookDelivery',
                                foreign_key: :automation_id, dependent: :delete_all, inverse_of: :automation

  encrypts :webhook_secret_jabvox if Jabvox.encryption_configured?

  # Todo lo que esta automatización apunta tiene que ser de su misma cuenta: sin esto se
  # podía enviar por la bandeja de otro cliente, gastar su saldo de SMS, renderizar sus
  # plantillas o mover tareas a su tablero.
  validates_account_scope :inbox, :email_template, :sms_provider, :target_stage

  validates :automation_type_jabvox, inclusion: { in: AUTOMATION_TYPES }
  validates :channel_type_jabvox, inclusion: { in: CHANNEL_TYPES }, allow_nil: true
  validates :channel_type_jabvox, presence: true, if: :send_message?
  validates :webhook_url_jabvox, presence: true, if: :webhook?
  validates :target_stage_id, presence: true, if: :time_based?
  validates :trigger_unit_jabvox, inclusion: { in: TRIGGER_UNITS }, allow_nil: true
  validate :trigger_amount_present, if: :time_based?
  validate :whatsapp_template_complete, if: :whatsapp_template?

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

  def whatsapp_template?
    send_message? && channel_type_jabvox == 'whatsapp_template'
  end

  # Momento a partir del cual la tarea se considera vencida. Las automatizaciones creadas
  # antes de existir la unidad solo tienen `trigger_hours_jabvox`, y se leen como horas.
  def trigger_cutoff
    value = trigger_value_jabvox || trigger_hours_jabvox
    return nil if value.blank?

    (trigger_unit_jabvox.presence || 'hours') == 'minutes' ? value.minutes.ago : value.hours.ago
  end

  private

  def trigger_amount_present
    return if (trigger_value_jabvox || trigger_hours_jabvox).to_i.positive?

    errors.add(:trigger_value_jabvox, 'debes indicar cuánto tiempo esperar')
  end

  def whatsapp_template_complete
    errors.add(:inbox, 'debes elegir la bandeja de WhatsApp') if inbox_id.blank?
    errors.add(:template_name_jabvox, 'debes elegir la plantilla') if template_name_jabvox.blank?
    # Por WhatsApp solo sale la plantilla. Un cuerpo escrito a mano aquí no se enviaría
    # nunca, así que guardarlo solo serviría para hacer creer que sí.
    self.message_body_jabvox = nil
  end
end
