class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000
  DELETE_MODES = %w[inbox_only inbox_conversations inbox_leads_conversations].freeze

  def perform(object, user = nil, ip = nil, delete_mode = nil, target_inbox_id = nil)
    if object.is_a?(Inbox)
      purge_inbox_associations(object, delete_mode, target_inbox_id)
    elsif object.is_a?(Conversation)
      JabvoxKanbanConversationStage.where(conversation_id: object.id).delete_all
      purge_heavy_associations(object)
    else
      purge_heavy_associations(object)
    end
    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def purge_inbox_associations(inbox, delete_mode, target_inbox_id = nil)
    # Remove records with real FK constraints before inbox deletion
    JabvoxKanbanFunnelInbox.where(inbox_id: inbox.id).delete_all
    JabvoxKanbanStageAutomation.where(inbox_id: inbox.id).delete_all
    JabvoxResponseBotConfig.where(inbox_id: inbox.id).delete_all

    mode = DELETE_MODES.include?(delete_mode) ? delete_mode : 'inbox_conversations'

    case mode
    when 'inbox_leads_conversations'
      purge_inbox_leads(inbox)
      purge_conversation_jabvox_associations(inbox)
      batch_destroy(inbox.conversations)
      batch_destroy(inbox.contact_inboxes)
      batch_destroy(inbox.reporting_events)
    when 'inbox_only'
      move_conversations_to_inbox(inbox, target_inbox_id)
      batch_destroy(inbox.contact_inboxes)
      batch_destroy(inbox.reporting_events)
    else
      purge_conversation_jabvox_associations(inbox)
      batch_destroy(inbox.conversations)
      batch_destroy(inbox.contact_inboxes)
      batch_destroy(inbox.reporting_events)
    end
  end

  def find_or_create_archive_inbox(inbox)
    account      = inbox.account
    archive_name = "Archivo - #{inbox.name}"
    account.inboxes.find_by(name: archive_name) ||
      account.inboxes.create!(
        name: archive_name,
        channel: Channel::Api.create!(account: account),
        timezone: inbox.timezone
      )
  end

  def move_conversations_to_inbox(inbox, target_inbox_id)
    target_id = if target_inbox_id.to_s == 'auto'
                  find_or_create_archive_inbox(inbox).id
                else
                  target_inbox_id.to_i
                end
    return unless target_id.positive?

    contact_ids = inbox.conversations.distinct.pluck(:contact_id).compact

    if contact_ids.any?
      existing_map = ContactInbox.where(inbox_id: target_id, contact_id: contact_ids).index_by(&:contact_id)
      missing_ids  = contact_ids - existing_map.keys

      if missing_ids.any?
        now = Time.current
        ContactInbox.insert_all!(missing_ids.map do |cid|
          { contact_id: cid, inbox_id: target_id, source_id: SecureRandom.uuid,
            pubsub_token: SecureRandom.hex, hmac_verified: false,
            created_at: now, updated_at: now }
        end)
        existing_map = ContactInbox.where(inbox_id: target_id, contact_id: contact_ids).index_by(&:contact_id)
      end

      inbox.conversations.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each do |conv|
          ci = existing_map[conv.contact_id]
          conv.update_columns(inbox_id: target_id, contact_inbox_id: ci&.id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end

    # rubocop:disable Rails/SkipsModelValidations
    inbox.messages.in_batches(of: BATCH_SIZE).update_all(inbox_id: target_id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def purge_conversation_jabvox_associations(inbox)
    conversation_ids = inbox.conversations.select(:id)
    JabvoxKanbanConversationStage.where(conversation_id: conversation_ids).delete_all
  end

  def purge_inbox_leads(inbox)
    contact_ids = inbox.contact_inboxes.pluck(:contact_id)
    return if contact_ids.empty?

    lead_ids = inbox.account.jabvox_leads.where(contact_id: contact_ids).pluck(:id)
    return if lead_ids.empty?

    JabvoxKanbanConversationStage.where(jabvox_lead_id: lead_ids).delete_all
    inbox.account.jabvox_leads.where(id: lead_ids).delete_all

    contact_ids.each_slice(BATCH_SIZE) do |slice|
      slice.each do |contact_id|
        contact = inbox.account.contacts.find_by(id: contact_id)
        next unless contact

        conv_ids = contact.conversations.select(:id)
        JabvoxKanbanConversationStage.where(conversation_id: conv_ids).delete_all
        JabvoxCalendarEvent.where(contact_id: contact_id).delete_all
        JabvoxSmsMessage.where(contact_id: contact_id).delete_all
        contact.destroy!
      end
    end
  end

  def heavy_associations
    {
      Account => %i[jabvox_leads conversations contacts inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    if object.respond_to?(:conversations)
      JabvoxKanbanConversationStage.where(conversation_id: object.conversations.select(:id)).delete_all
    end

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end
end

DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
