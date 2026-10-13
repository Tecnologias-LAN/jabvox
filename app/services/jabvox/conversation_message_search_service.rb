# frozen_string_literal: true

# Búsqueda de mensajes DENTRO de una conversación o de un contacto (todas sus conversaciones).
# A diferencia del SearchService global, acota siempre a un conjunto pequeño (una conversación,
# o las conversaciones de un contacto), así que es rápido y no impacta a otras cuentas.
#
# Busca en:
#   - messages.content (texto)
#   - attachments.meta->>'transcribed_text' (transcripción de notas de voz / grabaciones)
#   - nombre del adjunto (blob filename vía active_storage)
#
# Reglas de seguridad:
#   - SIEMPRE parte de current_account (aislamiento multi-cuenta).
#   - Respeta las inboxes accesibles del usuario (salvo admin o acceso a todas).
#   - Límite duro de resultados (nunca devuelve miles): paginado + cap.
# rubocop:disable Style/ClassAndModuleChildren
class Jabvox::ConversationMessageSearchService
  PER_PAGE = 20
  MAX_RESULTS = 200       # cap duro: jamás recorre/retorna más que esto
  MIN_QUERY_LENGTH = 2    # evita barridos con 1 carácter
  SNIPPET_RADIUS = 60     # caracteres de contexto alrededor de la coincidencia

  pattr_initialize [:account!, :user!, :params!]

  def perform
    return empty if query.length < MIN_QUERY_LENGTH

    scope = base_scope
    return empty if scope.nil?

    records = scope
              .where(match_condition, q: like_pattern)
              .reorder('messages.created_at DESC')
              .page(page).per(PER_PAGE)
              .limit(MAX_RESULTS)

    {
      messages: records.map { |m| serialize(m) },
      page: page,
      query: query
    }
  end

  private

  def query
    @query ||= params[:q].to_s.strip
  end

  def page
    @page ||= [params[:page].to_i, 1].max
  end

  # Escape de comodines LIKE + acotado de longitud (anti-DoS por patrón costoso).
  def like_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(query[0, 100])}%"
  end

  # Mensajes base: por conversación, o por contacto (todas sus conversaciones). SIEMPRE
  # dentro de la cuenta y de las inboxes accesibles. Devuelve nil si no hay acceso/target.
  def base_scope
    msgs = account_messages
    return nil if msgs.nil?

    msgs.left_joins(attachments: { file_attachment: :blob })
        .includes(:attachments, :sender)
  end

  def account_messages
    if params[:conversation_id].present?
      conversation = accessible_conversations.find_by(display_id: params[:conversation_id])
      return nil if conversation.nil?

      conversation.messages
    elsif params[:contact_id].present?
      contact = account.contacts.find_by(id: params[:contact_id])
      return nil if contact.nil?

      accessible_conversations.where(contact_id: contact.id).then do |convs|
        account.messages.where(conversation_id: convs.select(:id))
      end
    end
  end

  # Conversaciones de la cuenta visibles para el usuario (filtra por inboxes salvo admin).
  def accessible_conversations
    scope = account.conversations
    scope = scope.where(inbox_id: accessible_inbox_ids) unless skip_inbox_filter?
    scope
  end

  # content OR transcripción de audio OR nombre del adjunto (todos ILIKE, con DISTINCT por el join).
  def match_condition
    <<~SQL.squish
      messages.content ILIKE :q
      OR attachments.meta->>'transcribed_text' ILIKE :q
      OR active_storage_blobs.filename ILIKE :q
    SQL
  end

  def serialize(message)
    {
      id: message.id,
      conversation_id: message.conversation_id,
      conversation_display_id: message.conversation&.display_id,
      message_type: message.message_type,
      content: message.content,
      snippet: snippet_for(message),
      created_at: message.created_at.to_i,
      sender_name: message.sender&.try(:name)
    }
  end

  # Fragmento con la coincidencia resaltable: busca el término en content, transcripción o
  # nombre de adjunto y devuelve un recorte alrededor para mostrar en el dropdown.
  def snippet_for(message)
    haystack = [message.content, transcribed_text(message), attachment_names(message)]
               .compact.join(' · ')
    return haystack[0, 140] if query.blank?

    idx = haystack.downcase.index(query.downcase)
    return haystack[0, 140] if idx.nil?

    from = [idx - SNIPPET_RADIUS, 0].max
    prefix = from.positive? ? '…' : ''
    "#{prefix}#{haystack[from, SNIPPET_RADIUS * 2]}".strip
  end

  def transcribed_text(message)
    message.attachments.filter_map { |a| a.meta&.dig('transcribed_text') }.join(' ').presence
  end

  def attachment_names(message)
    message.attachments.filter_map { |a| a.file.attached? ? a.file.filename.to_s : nil }.join(' ').presence
  end

  def accessible_inbox_ids
    @accessible_inbox_ids ||= user.assigned_inboxes.pluck(:id)
  end

  def skip_inbox_filter?
    account_user&.administrator? || accessible_inbox_ids.sort == account.inboxes.pluck(:id).sort
  end

  def account_user
    @account_user ||= account.account_users.find_by(user: user)
  end

  def empty
    { messages: [], page: page, query: query }
  end
end
# rubocop:enable Style/ClassAndModuleChildren
