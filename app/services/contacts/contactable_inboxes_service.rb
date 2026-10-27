class Contacts::ContactableInboxesService
  pattr_initialize [:contact!]

  def get
    account = contact.account
    account.inboxes.filter_map { |inbox| get_contactable_inbox(inbox) }
  end

  private

  def get_contactable_inbox(inbox)
    case inbox.channel_type
    when 'Channel::TwilioSms'
      twilio_contactable_inbox(inbox)
    when 'Channel::Whatsapp'
      whatsapp_contactable_inbox(inbox)
    when 'Channel::Sms'
      sms_contactable_inbox(inbox)
    when 'Channel::Email'
      email_contactable_inbox(inbox)
    when 'Channel::Api'
      api_contactable_inbox(inbox)
    when 'Channel::WebWidget'
      website_contactable_inbox(inbox)
    end
  end

  def website_contactable_inbox(inbox)
    latest_contact_inbox = inbox.contact_inboxes.where(contact: @contact).last
    return unless latest_contact_inbox
    # FIXME : change this when multiple conversations comes in
    return if latest_contact_inbox.conversations.present?

    { source_id: latest_contact_inbox.source_id, inbox: inbox }
  end

  def api_contactable_inbox(inbox)
    latest_contact_inbox = inbox.contact_inboxes.where(contact: @contact).last
    source_id = latest_contact_inbox&.source_id || SecureRandom.uuid

    { source_id: source_id, inbox: inbox }
  end

  def email_contactable_inbox(inbox)
    return if @contact.email.blank?

    { source_id: @contact.email, inbox: inbox }
  end

  def whatsapp_contactable_inbox(inbox)
    # Prioridad teléfono > username/BSUID: si el contacto tiene número se inicia por él
    # (sin el '+', formato que usa la Cloud API). Si NO tiene número pero sí existe un
    # contact_inbox de esta bandeja cuyo source_id es un BSUID (llegó un @usuario sin
    # teléfono), se inicia por ese identificador. Si no hay ninguno, no es contactable.
    source_id = whatsapp_source_id(inbox)
    return if source_id.blank?

    { source_id: source_id, inbox: inbox }
  end

  def whatsapp_source_id(inbox)
    return @contact.phone_number.delete('+') if @contact.phone_number.present?

    inbox.contact_inboxes
         .where(contact: @contact)
         .where('source_id ~ ?', RegexHelper::WHATSAPP_BSUID_SQL_PATTERN)
         .order(created_at: :desc)
         .first&.source_id
  end

  def sms_contactable_inbox(inbox)
    return if @contact.phone_number.blank?

    { source_id: @contact.phone_number, inbox: inbox }
  end

  def twilio_contactable_inbox(inbox)
    return if @contact.phone_number.blank?

    case inbox.channel.medium
    when 'sms'
      { source_id: @contact.phone_number, inbox: inbox }
    when 'whatsapp'
      { source_id: "whatsapp:#{@contact.phone_number}", inbox: inbox }
    end
  end
end

Contacts::ContactableInboxesService.prepend_mod_with('Contacts::ContactableInboxesService')
