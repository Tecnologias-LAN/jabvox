# == Schema Information
#
# Table name: webhooks
#
#  id            :bigint           not null, primary key
#  conditions    :jsonb            not null
#  name          :string
#  secret        :string
#  subscriptions :jsonb
#  url           :text
#  webhook_type  :integer          default("account_type")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer
#  inbox_id      :integer
#
# Indexes
#
#  index_webhooks_on_account_id_and_url  (account_id,url) UNIQUE
#

class Webhook < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true

  include WebhookSecretable

  validates :account_id, presence: true
  validates :url, uniqueness: { scope: [:account_id] }, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validate :validate_webhook_subscriptions
  enum webhook_type: { account_type: 0, inbox_type: 1 }

  ALLOWED_WEBHOOK_EVENTS = %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                              message_created message_updated webwidget_triggered inbox_created inbox_updated
                              conversation_typing_on conversation_typing_off].freeze

  # ----- Reglas de entrega (Jabvox) -----------------------------------------
  # Evalúa si este webhook debe dispararse para un payload/inbox dados, según las
  # `conditions` opcionales. Sin reglas definidas -> siempre entrega (comportamiento
  # histórico). Lo usa WebhookListener antes de encolar el WebhookJob.
  # Pensado para el webhook de Hermes: "responde solo estas bandejas", "no respondas
  # los de etiqueta X", "responde solo en horario".
  def deliverable_for?(payload, inbox)
    return true if conditions.blank?

    inbox_allowed?(inbox) && labels_allowed?(payload) && within_working_hours?(inbox)
  end

  private

  def inbox_allowed?(inbox)
    allowed = Array(conditions['allowed_inbox_ids']).map(&:to_i).reject(&:zero?)
    return true if allowed.empty?

    inbox.present? && allowed.include?(inbox.id)
  end

  # Excluye la conversación si tiene alguna de las etiquetas vetadas. Las labels
  # viajan en el payload estándar: payload[:conversation][:labels].
  def labels_allowed?(payload)
    excluded = Array(conditions['excluded_labels']).map { |l| l.to_s.strip.downcase }.reject(&:blank?)
    return true if excluded.empty?

    convo_labels = Array(payload.dig(:conversation, :labels) || payload.dig('conversation', 'labels'))
                   .map { |l| l.to_s.strip.downcase }
    (excluded & convo_labels).empty?
  end

  # Solo dispara dentro del horario laboral del inbox (modelo WorkingHour). Si el
  # inbox no tiene horario configurado, no bloquea (deja pasar).
  def within_working_hours?(inbox)
    return true unless ActiveModel::Type::Boolean.new.cast(conditions['within_working_hours'])
    return true if inbox.blank? || !inbox.working_hours_enabled?

    today = inbox.working_hours.find_by(day_of_week: Time.zone.now.in_time_zone(inbox.timezone).to_date.wday)
    today.present? && today.open_now?
  end

  public

  def validate_webhook_subscriptions
    invalid_subscriptions = !subscriptions.instance_of?(Array) ||
                            subscriptions.blank? ||
                            (subscriptions.uniq - ALLOWED_WEBHOOK_EVENTS).length.positive?
    errors.add(:subscriptions, I18n.t('errors.webhook.invalid')) if invalid_subscriptions
  end
end

Webhook.include_mod_with('Audit::Webhook')
