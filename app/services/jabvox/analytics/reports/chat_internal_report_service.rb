# frozen_string_literal: true

# Reporte interno de "Chat Interno" para el módulo Analytics de Jabvox.
#
# Fuentes:
#   - jabvox_internal_chats   : el chat (tiene account_id, chat_type, created_by_id).
#   - jabvox_internal_messages: los mensajes (NO tienen account_id; se acotan a la
#     cuenta vía chat_id => jabvox_internal_chats.account_id).
#   - jabvox_internal_chat_members: miembros del chat (tampoco tienen account_id).
#
# SEGURIDAD: toda consulta arranca de account.jabvox_internal_chats. Para mensajes
# y miembros se hace join contra esa asociación, de modo que el account_id viaja
# siempre por el query de ActiveRecord y es imposible filtrar otra cuenta.
#
# date_from/date_to acotan created_at (de chats o de mensajes según la sección).
#
# NOTA: el esquema NO tiene columnas de estado abierto/cerrado/resuelto. Lo más
# cercano es chat_type (direct/group_chat). Por eso "by_status" reporta el desglose
# por chat_type y la sección de resolución se marca { available: false }.
class Jabvox::Analytics::Reports::ChatInternalReportService
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
      by_type: by_type,
      by_sender: by_sender,
      by_resolution: by_resolution
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

  # chat_type solicitado (direct/group_chat). Acepta clave chat_type o status.
  def filter_chat_type
    filters['chat_type'].presence || filters['status'].presence
  end

  # Scope base de chats: SIEMPRE arranca de la asociación de la cuenta.
  # Filtros: created_by_id (agente creador) y chat_type.
  def chats_scope
    relation = account.jabvox_internal_chats
    relation = relation.where('jabvox_internal_chats.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('jabvox_internal_chats.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(created_by_id: filter_agent_id) if filter_agent_id
    relation = relation.where(chat_type: filter_chat_type) if filter_chat_type
    relation
  end

  # Scope base de mensajes: acotado a la cuenta vía la asociación de chats.
  # Los mensajes no tienen account_id propio, por eso se unen por chat_id.
  # El filtro chat_type viaja por la subconsulta de chats (chats_scope).
  def messages_scope
    relation = JabvoxInternalMessage.where(chat_id: chats_scope.select(:id))
    relation = relation.where('jabvox_internal_messages.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('jabvox_internal_messages.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(sender_id: filter_agent_id) if filter_agent_id
    relation
  end

  def summary
    total_chats = chats_scope.count
    total_messages = messages_scope.count
    {
      total_chats: total_chats,
      total_messages: total_messages,
      active_senders: messages_scope.distinct.count(:sender_id),
      avg_messages_per_chat: total_chats.positive? ? (total_messages.to_f / total_chats).round(2) : 0.0
    }
  end

  # Serie temporal diaria: chats creados y mensajes enviados por día.
  def series
    chats_by_day = chats_scope.group('DATE(jabvox_internal_chats.created_at)').count
    messages_by_day = messages_scope.group('DATE(jabvox_internal_messages.created_at)').count
    days = (chats_by_day.keys + messages_by_day.keys).uniq.sort
    days.map do |day|
      {
        date: day.to_s,
        chats: chats_by_day[day] || 0,
        messages: messages_by_day[day] || 0
      }
    end
  end

  # Desglose de chats por chat_type (direct/group_chat). No hay estado
  # open/closed; chat_type es lo más cercano a una clasificación de chat.
  def by_type
    chats_scope.group(:chat_type).count.map do |chat_type, count|
      { chat_type: chat_type, count: count }
    end
  end

  # Mensajes por emisor (sender_id => users). Acotado a la cuenta por join.
  def by_sender
    counts = messages_scope.group(:sender_id).count
    names = sender_names(counts.keys)
    counts.map do |sender_id, count|
      { sender_id: sender_id, name: names[sender_id], count: count }
    end
  end

  # Nombres de los emisores en una sola query, sin exponer otras cuentas
  # (los ids ya provienen de mensajes acotados a la cuenta).
  def sender_names(sender_ids)
    return {} if sender_ids.empty?

    User.where(id: sender_ids).pluck(:id, :name).to_h
  end

  # TODO: el esquema de Chat Interno (jabvox_internal_chats / _messages /
  # _chat_members) no tiene columna de estado open/closed/resolved. Si en el
  # futuro se agrega (p. ej. un campo status en jabvox_internal_chats),
  # implementar aquí el desglose por estado de resolución.
  def by_resolution
    { available: false, note: 'No open/closed/resolved column exists on internal chat tables; closest is chat_type (see by_type).' }
  end
end
