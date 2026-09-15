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
  # crearon por separado y cada uno disparó su propio Jabvox::ContactLeadsIntegration),
  # mover el lead del mergee al mismo account_id+contact_id violaría el índice único
  # index_jabvox_leads_on_account_id_and_contact_id. En ese caso se conserva el lead del
  # base y el del mergee queda para que merge_and_remove_mergee_contact lo borre más abajo
  # (ese borrado usa DELETE, no UPDATE, así que no colisiona).
  def merge_leads
    return unless defined?(JabvoxLead)
    return if JabvoxLead.exists?(contact_id: @base_contact.id)

    JabvoxLead.where(contact_id: @mergee_contact.id).update_all(contact_id: @base_contact.id)
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
    lead_ids = JabvoxLead.where(contact_id: contact.id).pluck(:id)
    JabvoxKanbanConversationStage.where(conversation_id: contact.conversations.select(:id)).or(
      JabvoxKanbanConversationStage.where(jabvox_lead_id: lead_ids)
    ).delete_all
    JabvoxCalendarEvent.where(contact_id: contact.id).delete_all
    JabvoxLead.where(id: lead_ids).delete_all
    JabvoxSmsMessage.where(contact_id: contact.id).delete_all
    contact.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    @base_contact.update!(merged_attributes)
  end
end
