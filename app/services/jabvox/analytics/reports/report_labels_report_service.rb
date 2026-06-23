# frozen_string_literal: true

# Reporte "Etiquetas (Informes)" (key: report_labels).
#
# Mide el uso de etiquetas (labels) sobre las conversaciones de la cuenta a
# partir de las taggings de ActsAsTaggableOn:
#
#   - taggings : tag_id, taggable_type, taggable_id, context, created_at.
#                NO tiene account_id propio. Para etiquetas de conversaciones se
#                acota SIEMPRE con taggable_type = 'Conversation' y
#                taggable_id IN (conversaciones de la cuenta) -> nunca global.
#   - tags     : id, name (se resuelve el nombre legible vía
#                ActsAsTaggableOn::Tag, acotado a los tag_id observados).
#   - conversations : account.conversations provee el universo de ids válidos.
#
# SEGURIDAD: toda consulta de taggings filtra por
# taggable_id IN (account.conversations.select(:id)); el account_id viaja
# siempre dentro del query de ActiveRecord. No hay `.all` global ni SQL crudo
# con el account_id interpolado.
#
# date_from/date_to acotan taggings.created_at (momento en que se etiquetó);
# se manejan nil (sin filtro de fecha).
class Jabvox::Analytics::Reports::ReportLabelsReportService
  TAGGABLE_TYPE = 'Conversation'

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: build_summary,
      series: build_series,
      by_label: build_by_label
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Id de agente solicitado (agent_id o user_id en @filters).
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def filter_status
    filters['status'].presence
  end

  def filter_inbox_id
    @filter_inbox_id ||= filters['inbox_id'].presence&.to_i
  end

  # Ids de las conversaciones de la cuenta (subquery, nunca materializada en
  # memoria) para acotar las taggings al universo de la cuenta. Los filtros
  # adicionales (assignee_id, status, inbox_id) se aplican aquí, de modo que las
  # taggings quedan acotadas al subconjunto de conversaciones que cumplen.
  def account_conversation_ids
    scope = account.conversations
    scope = scope.where(assignee_id: filter_agent_id) if filter_agent_id
    scope = scope.where(status: filter_status) if filter_status
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope.select(:id)
  end

  # Scope base de taggings: SIEMPRE acotado a conversaciones de la cuenta.
  def taggings_scope
    scope = ActsAsTaggableOn::Tagging
            .where(taggable_type: TAGGABLE_TYPE, taggable_id: account_conversation_ids)
    scope = scope.where('taggings.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('taggings.created_at <= ?', date_to) if date_to.present?
    scope
  end

  def build_summary
    {
      total_taggings: taggings_scope.count,
      distinct_labels: taggings_scope.distinct.count(:tag_id),
      tagged_conversations: taggings_scope.distinct.count(:taggable_id)
    }
  end

  # Serie temporal diaria: cantidad de etiquetados por día.
  def build_series
    taggings_scope.group('DATE(taggings.created_at)').count.sort.map do |day, count|
      { date: day.to_s, taggings: count }
    end
  end

  # Top etiquetas por uso: conteo por tag_id, resuelto a tag.name. Ordenado de
  # mayor a menor uso. Incluye también conversaciones distintas por etiqueta.
  def build_by_label
    counts = taggings_scope.group(:tag_id).count
    conversation_counts = taggings_scope.group(:tag_id).distinct.count(:taggable_id)
    names = tag_names(counts.keys)

    rows = counts.map do |tag_id, count|
      {
        tag_id: tag_id,
        name: names[tag_id],
        taggings: count,
        conversations: conversation_counts[tag_id].to_i
      }
    end
    rows.sort_by { |row| -row[:taggings] }
  end

  # Nombres de las etiquetas en una sola query, acotada a los tag_id observados
  # (que ya provienen de taggings de la cuenta).
  def tag_names(tag_ids)
    return {} if tag_ids.empty?

    ActsAsTaggableOn::Tag.where(id: tag_ids).pluck(:id, :name).to_h
  end
end
