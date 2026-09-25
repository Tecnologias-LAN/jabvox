class ContactMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_contact!, :mergee_contact!]

  def perform
    # This case happens when an agent updates a contact email in dashboard,
    # while the contact also update his email via email collect box
    return @base_contact if base_contact.id == mergee_contact.id

    ActiveRecord::Base.transaction do
      validate_contacts
      merge_leads
      merge_conversations
      merge_messages
      merge_contact_inboxes
      merge_contact_notes
      merge_and_remove_mergee_contact
    end
    @base_contact
  end

  private

  def validate_contacts
    return if belongs_to_account?(@base_contact) && belongs_to_account?(@mergee_contact)

    raise StandardError, 'contact does not belong to the account'
  end

  def belongs_to_account?(contact)
    @account.id == contact.account_id
  end

  # Si el contacto base YA tiene su propio lead (el caso común: ambos contactos se
  # Datos comerciales de Jabvox al fusionar: los del contacto BASE mandan y solo se rellena
  # lo que tenga vacío, igual que hace el resto del merge con los atributos.
  #
  # Antes esto movía la fila de `jabvox_leads` del mergee al base; al vivir esos datos en el
  # propio contacto, lo que corresponde es completarlos campo a campo.
  JABVOX_MERGE_FIELDS = %i[jabvox_campaign_id jabvox_affiliate_id assignee_id became_lead_at_jabvox].freeze

  def merge_leads
    attrs = fill_blank_jabvox_fields
    attrs[:is_sold_jabvox] = true if @mergee_contact.is_sold_jabvox? && !@base_contact.is_sold_jabvox?
    attrs.merge!(merged_custom_fields)

    @base_contact.update!(attrs) if attrs.any?
  end

  def fill_blank_jabvox_fields
    JABVOX_MERGE_FIELDS.each_with_object({}) do |field, attrs|
      next if @base_contact[field].present? || @mergee_contact[field].blank?

      attrs[field] = @mergee_contact[field]
    end
  end

  # Los campos personalizados se fusionan con los del base ganando, para no perder lo que
  # cada uno tuviera por separado.
  def merged_custom_fields
    base = @base_contact.custom_fields_jabvox || {}
    merged = (@mergee_contact.custom_fields_jabvox || {}).merge(base)
    merged == base ? {} : { custom_fields_jabvox: merged }
  end

  def merge_conversations
    Conversation.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_contact_notes
    Note.where(contact_id: @mergee_contact.id, account_id: @mergee_contact.account_id).update(contact_id: @base_contact.id)
  end

  def merge_messages
    Message.where(sender: @mergee_contact).update(sender: @base_contact)
  end

  def merge_contact_inboxes
    ContactInbox.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_and_remove_mergee_contact
    mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
    base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
    mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank

    # attributes in base contact are given preference
    merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)

    contact = @mergee_contact.reload
    JabvoxKanbanConversationStage.where(conversation_id: contact.conversations.select(:id)).or(
      JabvoxKanbanConversationStage.where(contact_id: contact.id)
    ).delete_all
    JabvoxCalendarEvent.where(contact_id: contact.id).delete_all
    JabvoxSmsMessage.where(contact_id: contact.id).delete_all
    contact.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    @base_contact.update!(merged_attributes)
  end
end
