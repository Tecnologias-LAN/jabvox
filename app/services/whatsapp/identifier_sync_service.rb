class Whatsapp::IdentifierSyncService
  pattr_initialize [:contact_inbox!, :contact]

  def perform(source_ids: [], username: nil, phone_number: nil)
    create_contact_inboxes(source_ids)
    update_contact(username, phone_number)
  end

  private

  def create_contact_inboxes(source_ids)
    source_ids.compact_blank.uniq.each do |source_id|
      next if inbox.contact_inboxes.exists?(source_id: source_id)

      inbox.contact_inboxes.create!(contact: synced_contact, source_id: source_id)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent webhook (e.g. a status update bypassing the per-contact
      # mutex) just inserted the same (inbox_id, source_id). Treat it as a
      # no-op instead of falling through to ContactInboxBuilder's retry path,
      # which would scramble the freshly-written row.
    end
  end

  def update_contact(username, phone_number)
    return if synced_contact.blank?

    update_contact_phone_number(phone_number)
    update_contact_username(username)
  end

  def update_contact_phone_number(phone_number)
    phone_number = phone_number.presence
    return if phone_number.blank? || synced_contact.phone_number.present?
    return if synced_contact.account.contacts.where(phone_number: phone_number).where.not(id: synced_contact.id).exists?

    synced_contact.update!(phone_number: phone_number)
  end

  def update_contact_username(username)
    username = normalize_username(username)
    return if username.blank?

    attrs = { additional_attributes: additional_attributes_with_username(username) }
    # Columna de primera clase: solo se rellena si está vacía y el @usuario no lo tiene ya
    # otro contacto de la cuenta (mismo criterio anti-duplicado que el teléfono). El jsonb
    # se mantiene siempre para compatibilidad hacia atrás.
    attrs[:username] = username if assignable_username?(username)
    synced_contact.update!(attrs)
  end

  def assignable_username?(username)
    return false if synced_contact.username.present?

    !synced_contact.account.contacts
                   .where('LOWER(username) = ?', username.downcase)
                   .where.not(id: synced_contact.id)
                   .exists?
  end

  def synced_contact
    @synced_contact ||= contact || contact_inbox.contact
  end

  def inbox
    @inbox ||= contact_inbox.inbox
  end

  def normalize_username(value)
    value.to_s.sub(/\A@+/, '').presence
  end

  def additional_attributes_with_username(username)
    attributes = synced_contact.additional_attributes.deep_dup
    social_profiles = attributes['social_profiles'] || {}
    social_profiles['whatsapp'] = username

    attributes.merge(
      'social_profiles' => social_profiles,
      'social_whatsapp_user_name' => username
    )
  end
end
