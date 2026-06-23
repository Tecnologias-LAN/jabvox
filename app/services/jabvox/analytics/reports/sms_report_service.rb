# frozen_string_literal: true

# Reporte interno de SMS para el módulo Analytics de Jabvox.
#
# Fuente principal: jabvox_sms_messages (siempre acotado por la cuenta vía la
# asociación account.jabvox_sms_messages, nunca un scope global).
#
# Agrupa por estado (status), por campaña (jabvox_sms_campaign_id) y por día
# sobre created_at. La serie temporal usa además sent_at (nullable, solo
# poblado al enviar) para distinguir envíos efectivos de mensajes creados.
#
# NOTA: El esquema SMS no tiene columna de usuario/agente en ninguna tabla
# (mensaje, campaña ni proveedor). Por eso la sección by_agent se devuelve
# como { available: false }. Ver TODO más abajo.
class Jabvox::Analytics::Reports::SmsReportService
  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: summary,
      series: series,
      by_status: by_status,
      by_campaign: by_campaign,
      by_agent: by_agent
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Scope base: SIEMPRE arranca de la asociación de la cuenta.
  # Filtros: status, jabvox_sms_campaign_id (campaña) y contact_id. No hay
  # columna de usuario/agente, por eso agent_id no aplica.
  def scope
    relation = account.jabvox_sms_messages
    relation = relation.where('jabvox_sms_messages.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('jabvox_sms_messages.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(status: filters['status']) if filters['status'].present?
    relation = relation.where(jabvox_sms_campaign_id: filters['campaign_id'].to_i) if filters['campaign_id'].present?
    relation = relation.where(contact_id: filters['contact_id'].to_i) if filters['contact_id'].present?
    relation
  end

  def summary
    total = scope.count
    sent = scope.where(status: 'sent').count
    failed = scope.where(status: 'failed').count
    pending = scope.where(status: 'pending').count
    {
      total_messages: total,
      sent: sent,
      failed: failed,
      pending: pending,
      other: total - sent - failed - pending,
      delivery_rate: total.positive? ? (sent.to_f / total * 100).round(2) : 0.0
    }
  end

  # Serie temporal por día sobre created_at (mensajes creados) y sobre sent_at
  # (envíos efectivos; sent_at es nullable, solo cuenta los realmente enviados).
  def series
    created = scope.group('DATE(jabvox_sms_messages.created_at)').count
    sent = scope.where.not(sent_at: nil).group('DATE(jabvox_sms_messages.sent_at)').count
    days = (created.keys + sent.keys).uniq.sort
    days.map do |day|
      {
        date: day.to_s,
        created: created[day] || 0,
        sent: sent[day] || 0
      }
    end
  end

  def by_status
    scope.group(:status).count.map do |status, count|
      { status: status, count: count }
    end
  end

  def by_campaign
    scope.group(:jabvox_sms_campaign_id).count.map do |campaign_id, count|
      { campaign_id: campaign_id, name: campaign_name(campaign_id), count: count }
    end
  end

  def campaign_name(campaign_id)
    return nil if campaign_id.nil?

    campaign_names[campaign_id]
  end

  # Nombres de campaña acotados a la cuenta (asociación), en una sola query.
  def campaign_names
    @campaign_names ||= account.jabvox_sms_campaigns.pluck(:id, :name).to_h
  end

  # TODO: El esquema SMS actual (jabvox_sms_messages / jabvox_sms_campaigns /
  # jabvox_sms_providers) no tiene FK ni columna de usuario/agente, por lo que
  # la atribución por agente no es calculable. Si en el futuro se agrega
  # user_id/agent_id (al mensaje o a la campaña), implementar el agrupado aquí.
  def by_agent
    { available: false, note: 'No agent/user column exists on SMS tables; attribution not possible.' }
  end
end
