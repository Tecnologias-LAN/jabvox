# Dispatches one recurring task automation: resolves its recipients (lead contact, task
# assignees, lead contacts, manual address), renders the message, sends it through the chosen
# channel (email / sms / inbox), and records a JabvoxTaskAutomationRun for the audit trail
# shown on the board and calendar. Never raises to the scheduler — failures are logged on the
# run row so one bad automation can't break the batch.
class Jabvox::TaskAutomationDispatchService
  Recipient = Struct.new(:label, :email, :phone, :contact, keyword_init: true) do
    # A recipient with neither an email nor a phone can't receive anything.
    def empty_target?
      email.blank? && phone.blank?
    end
  end

  def initialize(automation)
    @automation = automation
    @account = automation.account
    @task = automation.task
    # Tras retirar Leads el contacto cuelga directamente de la tarea. Se conserva el
    # nombre `lead` en los destinatarios y en las plantillas porque es lo que ya tienen
    # guardado las automatizaciones existentes.
    @lead = @task.contact
  end

  # Sends to every resolved recipient and returns the created run.
  def perform
    reason = skip_reason
    return record_run(status: 'skipped', count: 0, detail: reason) if reason

    recipients = resolve_recipients
    return record_run(status: 'skipped', count: 0, detail: 'no_recipients') if recipients.empty?

    sent = 0
    errors = []
    recipients.each do |r|
      deliver(r)
      sent += 1
    rescue StandardError => e
      errors << "#{r.label}: #{e.message}"
    end

    record_run(status: run_status(sent, errors), count: sent, detail: errors.join('; ').presence)
  ensure
    # Skipped tasks keep their schedule so it resumes if reopened or restored.
    @automation.mark_ran! if @automation.persisted? && skip_reason.nil?
  end

  private

  def skip_reason
    return 'task_deleted' if @task.deleted_at_jabvox.present?
    return 'task_done' if @task.status_jabvox == 'done'

    nil
  end

  def run_status(sent, errors)
    return 'failed' if sent.zero? && errors.any?
    return 'partial' if errors.any?

    'sent'
  end

  # Build the recipient list from the automation's recipient kinds, de-duped by email/phone.
  def resolve_recipients
    list = []
    kinds = @automation.recipient_kinds
    list.concat(lead_recipients) if kinds.include?('lead')
    list.concat(assignee_recipients) if kinds.include?('assignees')
    list.concat(lead_contact_recipients) if kinds.include?('lead_contacts')
    list << manual_recipient if kinds.include?('manual')
    list.compact.uniq { |r| [r.email.to_s.downcase, r.phone.to_s] }.reject(&:empty_target?)
  end

  def lead_recipients
    contact = @lead
    return [] unless contact

    [Recipient.new(label: contact.name, email: contact.email,
                   phone: contact.phone_number, contact: contact)]
  end

  def assignee_recipients
    @task.assignees.map do |u|
      # Un responsable es un usuario (agente): tiene email pero NO teléfono ni contacto.
      # Para WhatsApp hace falta un contacto real, así que se usa el mapeado en la
      # automatización (responsable -> contacto). Para email se sigue usando su correo.
      mapped = @automation.assignee_contact_for(u.id)
      Recipient.new(
        label: u.name,
        email: u.email,
        phone: mapped&.phone_number,
        contact: mapped
      )
    end
  end

  # Los contactos-de-tarea vivían en jabvox_task_lead_contacts, tabla retirada con Leads. El
  # destinatario es ahora el propio contacto de la tarea.
  def lead_contact_recipients
    return [] unless @lead

    [Recipient.new(label: @lead.name, email: @lead.email,
                   phone: @lead.phone_number, contact: @lead)]
  end

  def manual_recipient
    Recipient.new(
      label: @automation.manual_email_jabvox.presence || @automation.manual_phone_jabvox,
      email: @automation.manual_email_jabvox, phone: @automation.manual_phone_jabvox, contact: nil
    )
  end

  def deliver(recipient)
    case @automation.channel_jabvox
    when 'email' then deliver_email(recipient)
    when 'sms' then deliver_sms(recipient)
    when 'whatsapp_template' then deliver_template(recipient)
    end
  end

  def deliver_email(recipient)
    raise 'sin_email' if recipient.email.blank?

    smtp = @account.jabvox_smtp_config
    raise 'sin_smtp' unless smtp

    Jabvox::EmailSenderService.new(
      account: @account, config: smtp, to: recipient.email,
      subject: render(email_subject), html_body: render(email_body),
      source: 'task', user: @automation.created_by
    ).deliver!
  end

  def deliver_sms(recipient)
    raise 'sin_telefono' if recipient.phone.blank?

    provider = @automation.sms_provider
    raise 'sin_proveedor_sms' unless provider

    Jabvox::SmsSenderService.new(provider).send_sms(
      phone: recipient.phone, message: render(@automation.body_jabvox),
      account: @account, contact: recipient.contact
    )
  end

  # Plantilla aprobada de WhatsApp. El texto libre solo sale dentro de la ventana de 24h y
  # una automatización programada dispara casi siempre fuera de ella.
  def deliver_template(recipient)
    # WhatsApp necesita un CONTACTO (con contact_inbox y conversación). El lead de la tarea
    # ya lo trae; un destinatario manual o un responsable solo traen un teléfono suelto, así
    # que se busca/crea el contacto por ese número en la cuenta. Antes esto fallaba siempre
    # con `sin_contacto` al mandar plantilla a una "Dirección manual".
    contact = recipient.contact || contact_from_phone(recipient.phone)
    raise 'sin_contacto' unless contact

    inbox = @automation.inbox
    raise 'sin_inbox' unless inbox
    raise 'sin_plantilla' if @automation.template_name_jabvox.blank?

    conversation = find_or_create_conversation(contact, inbox)
    raise 'sin_conversacion' unless conversation

    Messages::MessageBuilder.new(nil, conversation, {
                                   message_type: 'outgoing',
                                   content: @automation.template_name_jabvox,
                                   private: false,
                                   template_params: template_payload(contact)
                                 }).perform
  end

  # Contacto de la cuenta para un teléfono suelto (destinatario manual o responsable sin
  # contacto propio): se busca por el número normalizado y, si no existe, se crea. Devuelve
  # nil si no hay teléfono utilizable, para que caiga en `sin_contacto`.
  def contact_from_phone(phone)
    normalized = normalize_phone(phone)
    return nil if normalized.blank?

    @account.contacts.find_by(phone_number: normalized) ||
      @account.contacts.create!(name: normalized, phone_number: normalized)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Normaliza a E.164 best-effort: deja solo dígitos y antepone '+'. Un número ya con '+'
  # se respeta. Suficiente para que WhatsApp lo acepte; la normalización fina la hace el canal.
  def normalize_phone(phone)
    digits = phone.to_s.strip
    return '' if digits.blank?
    return digits if digits.start_with?('+')

    only = digits.gsub(/\D/, '')
    only.present? ? "+#{only}" : ''
  end

  def template_payload(contact)
    {
      name: @automation.template_name_jabvox,
      language: @automation.template_language_jabvox.presence || 'es',
      category: 'UTILITY',
      processed_params: Jabvox::AutomationTemplateParamsService.new(
        mapping: @automation.template_params_jabvox, contact: contact, task: @automation.task
      ).call
    }
  end

  def find_or_create_conversation(contact, inbox)
    # ContactInbox exige un source_id con formato propio de cada canal (para WhatsApp,
    # el teléfono sin '+'). find_or_create_by! sin source_id fallaba la validación
    # (-> sin_conversacion). ContactInboxBuilder lo genera correctamente por canal.
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return nil unless contact_inbox

    contact_inbox.conversations.last || Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox
    )
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    nil
  end

  def email_subject
    @automation.email_template&.subject.presence || @automation.subject_jabvox
  end

  def email_body
    @automation.email_template&.body.presence || @automation.body_jabvox
  end

  def render(text)
    return '' if text.blank?

    vars = {
      'task_title' => @task.title_jabvox.to_s,
      'board_name' => @task.board&.name_jabvox.to_s,
      'stage_name' => @task.stage&.name_jabvox.to_s,
      'lead_name' => @lead&.name.to_s
    }
    Liquid::Template.parse(text).render(vars)
  rescue Liquid::Error
    text
  end

  def record_run(status:, count:, detail: nil)
    JabvoxTaskAutomationRun.create!(
      account_id: @account.id, task_id: @task.id, automation_id: @automation.id,
      channel_jabvox: @automation.channel_jabvox, status_jabvox: status,
      recipients_count_jabvox: count, detail_jabvox: detail, run_at_jabvox: Time.current
    )
  end
end
