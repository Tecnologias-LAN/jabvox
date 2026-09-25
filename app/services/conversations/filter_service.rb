class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  # Los filtros por datos del CONTACTO comparan contra LOWER(columna), así que el valor debe
  # llegar en minúsculas o `equal_to` con mayúsculas no encontraría nada. El teléfono se
  # normaliza como en Contacts::FilterService, para que buscarlo con o sin '+' dé igual.
  CONTACT_TEXT_KEYS = %w[contact_name contact_email contact_identification].freeze

  def filter_values(query_hash)
    key = query_hash['attribute_key']
    return super unless CONTACT_TEXT_KEYS.include?(key) || key == 'contact_phone_number'

    value = query_hash['values'].is_a?(Array) ? query_hash['values'][0] : query_hash['values']
    return "+#{value&.delete('+')}" if key == 'contact_phone_number'

    value.is_a?(String) ? value.downcase : value
  end

  # Mismo criterio para los operadores de texto (contains / starts_with), que llegan por otra
  # vía y también se comparan contra LOWER(columna).
  def values_for_ilike(query_hash)
    return super unless CONTACT_TEXT_KEYS.include?(query_hash['attribute_key'])

    Array(query_hash['values']).map { |item| "%#{item.to_s.strip.downcase}%" }
  end

  def values_for_starts_with(query_hash)
    key = query_hash['attribute_key']
    return super unless CONTACT_TEXT_KEYS.include?(key) || key == 'contact_phone_number'

    Array(query_hash['values']).map { |item| "#{item.to_s.strip.downcase}%" }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end
end
