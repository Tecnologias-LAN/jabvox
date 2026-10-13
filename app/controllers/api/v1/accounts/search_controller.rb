class Api::V1::Accounts::SearchController < Api::V1::Accounts::BaseController
  def index
    @result = search('all')
  end

  def conversations
    @result = search('Conversation')
  end

  def contacts
    @result = search('Contact')
  end

  def messages
    @result = search('Message')
  end

  # Búsqueda de mensajes DENTRO de una conversación (?conversation_id=&q=) o de un contacto
  # (?contact_id=&q=): texto + transcripción de audio + nombre de adjunto. Servicio dedicado,
  # acotado y aislado por cuenta (no usa el SearchService global).
  def conversation_messages
    @result = Jabvox::ConversationMessageSearchService.new(
      account: Current.account, user: Current.user, params: params
    ).perform
    render json: @result
  end

  private

  def search(search_type)
    SearchService.new(
      current_user: Current.user,
      current_account: Current.account,
      search_type: search_type,
      params: params
    ).perform
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
