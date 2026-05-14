class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [])
    @account = account
    @contact_ids = Array(contact_ids).compact
  end

  def perform
    return if @contact_ids.blank?

    contacts.find_each do |contact|
      JabvoxKanbanConversationStage.where(conversation_id: contact.conversations.select(:id)).delete_all
      JabvoxCalendarEvent.where(contact_id: contact.id).delete_all
      JabvoxLead.where(contact_id: contact.id).delete_all
      JabvoxSmsMessage.where(contact_id: contact.id).delete_all
      contact.destroy!
    end
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end
end
