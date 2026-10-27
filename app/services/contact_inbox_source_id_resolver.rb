class ContactInboxSourceIdResolver
  # username_source_id: opcional, el source_id "username:<usuario>" de una conversación
  # importada de Evolution que solo conocía el username. Si existe un contact_inbox con ese
  # source_id, se reutiliza su contacto (reconexión): así el primer mensaje real de la persona
  # (que llega con número/BSUID) cae sobre el MISMO contacto/conversación del historial
  # importado, en vez de crear uno nuevo duplicado.
  pattr_initialize [:inbox!, :source_ids!, :contact_attributes!, { username_source_id: nil }]

  def perform
    existing_contact_inbox || reconnected_contact_inbox || create_contact_inbox
  end

  private

  def existing_contact_inbox
    normalized_source_ids.each do |source_id|
      contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id)
      return contact_inbox if contact_inbox
    end

    nil
  end

  # Reconexión por username: si llega un username en el webhook y ya existe un contact_inbox
  # importado con source_id "username:<usuario>", engancha los source_ids reales (número/BSUID)
  # a ESE contacto y devuelve su contact_inbox direccionable recién creado.
  def reconnected_contact_inbox
    return if username_source_id.blank?

    imported = inbox.contact_inboxes.find_by(source_id: username_source_id)
    return if imported.blank?

    addressable = normalized_source_ids.first
    return imported if addressable.blank?

    real_ci = inbox.contact_inboxes
                   .where(source_id: addressable)
                   .first_or_create!(contact: imported.contact)

    # Repunta las conversaciones del contact_inbox-username (historial importado) al
    # contact_inbox direccionable, para que el envío salga por número/BSUID y no por el
    # username (que Meta rechazaría). Sin esto, la conversación quedaría "pegada" al username.
    imported.conversations.update_all(contact_inbox_id: real_ci.id) # rubocop:disable Rails/SkipsModelValidations

    real_ci
  end

  def create_contact_inbox
    ::ContactInboxWithContactBuilder.new(
      source_id: normalized_source_ids.first,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform
  end

  def normalized_source_ids
    @normalized_source_ids ||= source_ids.compact_blank.uniq
  end
end
