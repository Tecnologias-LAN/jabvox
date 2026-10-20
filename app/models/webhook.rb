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

    inbox_allowed?(inbox) && labels_allowed?(payload) && within_schedule?(inbox)
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
    !excluded.intersect?(convo_labels)
  end

  # Solo dispara dentro del horario elegido en la regla. Prioridad:
  #   1) `schedule` propio del webhook (días + franja + zona) — lo que el usuario define aquí.
  #   2) compatibilidad: el viejo booleano `within_working_hours` (horario de la bandeja).
  # Sin ninguno -> no bloquea (deja pasar).
  def within_schedule?(inbox)
    sched = conditions['schedule']
    return within_custom_schedule?(sched) if sched.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(sched['enabled'])

    within_inbox_working_hours?(inbox)
  end

  # Horario PROPIO del webhook: { enabled, days:[0..6], start:"HH:MM", end:"HH:MM", timezone }.
  # days vacío = todos los días. Franja incompleta = no bloquea. 0=domingo..6=sábado.
  def within_custom_schedule?(sched)
    tz = sched['timezone'].presence || Time.zone.name
    now = Time.current.in_time_zone(tz)

    days = Array(sched['days']).map(&:to_i)
    return false if days.present? && days.exclude?(now.wday)

    start_min = parse_hhmm(sched['start'])
    end_min   = parse_hhmm(sched['end'])
    return true if start_min.nil? || end_min.nil?

    current_min = (now.hour * 60) + now.min
    if end_min >= start_min
      current_min.between?(start_min, end_min)
    else
      # Franja que cruza medianoche (ej. 22:00–06:00).
      current_min >= start_min || current_min <= end_min
    end
  end

  # Compatibilidad con la regla antigua: horario laboral del inbox (modelo WorkingHour).
  def within_inbox_working_hours?(inbox)
    return true unless ActiveModel::Type::Boolean.new.cast(conditions['within_working_hours'])
    return true if inbox.blank? || !inbox.working_hours_enabled?

    today = inbox.working_hours.find_by(day_of_week: Time.zone.now.in_time_zone(inbox.timezone).to_date.wday)
    today.present? && today.open_now?
  end

  # "HH:MM" -> minutos desde medianoche; nil si vacío/invalido.
  def parse_hhmm(value)
    str = value.to_s.strip
    return nil unless str =~ /\A(\d{1,2}):(\d{2})\z/

    h = Regexp.last_match(1).to_i
    m = Regexp.last_match(2).to_i
    return nil unless h.between?(0, 23) && m.between?(0, 59)

    (h * 60) + m
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
