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
    destroy_object!(object)
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  # Destroys the object, surfacing any failure to the logs instead of dying
  # silently in Sidekiq. For inboxes a callback on the dependent channel
  # (e.g. a WhatsApp webhook teardown calling out to Meta) can raise and abort
  # the whole deletion, leaving the inbox to reappear on reload. In that case
  # we log the real error and fall back to a callback-free deletion so the
  # record is actually removed.
  def destroy_object!(object)
    object.destroy!
  rescue StandardError => e
    Rails.logger.error("[DeleteObjectJob] destroy failed for #{object.class}##{object.id}: #{e.class} - #{e.message}")
    raise unless object.is_a?(Inbox)

    force_destroy_inbox(object)
  end

  # Last-resort inbox deletion: clear the remaining direct associations, then
  # drop the inbox and its channel without running callbacks (a channel
  # callback such as a WhatsApp webhook teardown may depend on a now-unreachable
  # external API and is what aborted the normal destroy).
  def force_destroy_inbox(inbox)
    channel = inbox.channel
    # Re-run the FK cleanup: the normal destroy! may have rolled back before
    # purge_inbox_associations' effects mattered, and these rows (RESTRICT FKs)
    # would otherwise block the callback-free delete below too.
    clear_inbox_fk_rows(inbox)
    inbox.campaigns.delete_all
    inbox.webhooks.delete_all
    inbox.hooks.delete_all
    inbox.inbox_members.delete_all
    inbox.working_hours.delete_all
    inbox.agent_bot_inbox&.delete
    inbox.inbox_assignment_policy&.delete
    inbox.delete
    channel&.delete
  end

  # Deletes every Jabvox row that holds a FK to this inbox WITHOUT ON DELETE
  # CASCADE (RESTRICT/NO ACTION). Missing any of these makes the inbox DELETE
  # raise ActiveRecord::InvalidForeignKey. jabvox_whatsapp_templates is CASCADE
  # but cleared too (belt-and-suspenders). Las tablas de batch/automation,
  # jabvox_whatsapp_flows (+ hijos) y jabvox_response_bot_configs eran las que
  # faltaban y hacían reaparecer la bandeja tras "eliminarla" (sobre todo las de
  # WhatsApp, que son las que suelen tener flows/response-bot asociados).
  def clear_inbox_fk_rows(inbox)
    JabvoxKanbanFunnelInbox.where(inbox_id: inbox.id).delete_all
    JabvoxKanbanStageAutomation.where(inbox_id: inbox.id).delete_all
    JabvoxTaskStageAutomation.where(inbox_id: inbox.id).delete_all
    JabvoxWhatsappTemplate.where(inbox_id: inbox.id).delete_all
    clear_bulk_whatsapp_rows(inbox)
    clear_task_automation_rows(inbox)
    clear_whatsapp_flow_rows(inbox)
    clear_response_bot_rows(inbox)
  end

  # Bulk WhatsApp batches (RESTRICT) y sus recipients (RESTRICT de vuelta): hijos
  # primero, porque delete_all no dispara dependent: :destroy.
  def clear_bulk_whatsapp_rows(inbox)
    batch_ids = JabvoxBulkWhatsappBatch.where(inbox_id: inbox.id).ids
    return if batch_ids.empty?

    JabvoxBulkWhatsappRecipient.where(bulk_whatsapp_batch_id: batch_ids).delete_all
    JabvoxBulkWhatsappBatch.where(id: batch_ids).delete_all
  end

  # Task automations (RESTRICT) y sus runs (RESTRICT de vuelta): hijos primero.
  def clear_task_automation_rows(inbox)
    automation_ids = JabvoxTaskAutomation.where(inbox_id: inbox.id).ids
    return if automation_ids.empty?

    JabvoxTaskAutomationRun.where(automation_id: automation_ids).delete_all
    JabvoxTaskAutomation.where(id: automation_ids).delete_all
  end

  # jabvox_whatsapp_flows tiene FK RESTRICT a inboxes, y sus hijos (versions,
  # submissions y los answers que cuelgan de submissions) tienen FK RESTRICT de
  # vuelta. Hay que borrar de abajo hacia arriba: answers -> submissions ->
  # versions -> flows. Eran la causa de que las bandejas de WhatsApp "se borraran"
  # pero reaparecieran al recargar.
  def clear_whatsapp_flow_rows(inbox)
    flow_ids = JabvoxWhatsappFlow.where(inbox_id: inbox.id).ids
    return if flow_ids.empty?

    submission_ids = JabvoxWhatsappFlowSubmission.where(jabvox_whatsapp_flow_id: flow_ids).ids
    JabvoxWhatsappFlowAnswer.where(jabvox_whatsapp_flow_submission_id: submission_ids).delete_all if submission_ids.any?
    JabvoxWhatsappFlowSubmission.where(jabvox_whatsapp_flow_id: flow_ids).delete_all
    JabvoxWhatsappFlowVersion.where(jabvox_whatsapp_flow_id: flow_ids).delete_all
    JabvoxWhatsappFlow.where(id: flow_ids).delete_all
  end

  # jabvox_response_bot_configs tiene FK RESTRICT a inboxes y no hay un modelo
  # Ruby propio en este repo, así que se limpia por SQL con el nombre de tabla.
  def clear_response_bot_rows(inbox)
    ActiveRecord::Base.connection.exec_delete(
      'DELETE FROM jabvox_response_bot_configs WHERE inbox_id = $1',
      'DeleteObjectJob clear_response_bot_rows',
      [ActiveRecord::Relation::QueryAttribute.new('inbox_id', inbox.id, ActiveRecord::Type::Integer.new)]
    )
  end

  def purge_inbox_associations(inbox, delete_mode, target_inbox_id = nil)
    # Remove records with real FK constraints before inbox deletion. Every table
    # with a FK to inboxes that is NOT ON DELETE CASCADE must be listed here (and
    # in clear_inbox_fk_rows below), or the inbox DELETE raises
    # ActiveRecord::InvalidForeignKey and the inbox reappears on reload.
    clear_inbox_fk_rows(inbox)

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

    JabvoxKanbanConversationStage.where(contact_id: contact_ids).delete_all
    # Las filas de tablas personalizadas (Asesorías, Casos…) cuelgan del contacto; se limpian
    # antes del delete_all sin callbacks. La FK es ON DELETE CASCADE, así que esto es un
    # refuerzo: el borrado nunca puede quedar bloqueado.
    JabvoxCustomTableRow.where(contact_id: contact_ids).delete_all

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
      Account => %i[conversations contacts inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    JabvoxKanbanConversationStage.where(conversation_id: object.conversations.select(:id)).delete_all if object.respond_to?(:conversations)

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
