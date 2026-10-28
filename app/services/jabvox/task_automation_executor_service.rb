# Runs the automations configured on the stage a task just entered: send a message to the
# contact (WhatsApp template/email/sms) and/or POST a secure webhook. Mirrors the kanban
# executor; time-based moves are handled separately by the scheduled time-automations service.
class Jabvox::TaskAutomationExecutorService
  # Un destinatario resuelto: puede ser el lead, un responsable (con su contacto mapeado) o
  # una dirección manual. Cada canal usa el campo que le sirve (email / phone / contact).
  Recipient = Struct.new(:label, :email, :phone, :contact, keyword_init: true) do
    def empty_target?
      email.blank? && phone.blank? && contact.nil?
    end
  end

  def initialize(task)
    @task = task
    @account = task.account
    @stage = task.stage
    # El contacto cuelga de la tarea desde que se retiró Leads.
    @contact = @task.contact
  end

  def perform
    @stage.automations.active.each do |automation|
      execute(automation)
    rescue StandardError => e
      Rails.logger.error("[TaskAutomation] id=#{automation.id} error=#{e.message}")
    end
  end

  private

  def execute(automation)
    case automation.automation_type_jabvox
    when 'send_message' then send_message(automation)
    when 'webhook' then Jabvox::TaskWebhookService.new(automation: automation, task: @task).perform
      # move_after_hours / move_if_inactive are handled by the scheduled time service.
    end
  end

  # Envía a CADA destinatario configurado (lead, responsables, manual). Antes iba siempre al
  # contacto de la tarea; ahora se resuelve la lista igual que en las automatizaciones de
  # tarea específica, con el mapeo responsable->contacto para WhatsApp.
  def send_message(automation)
    resolve_recipients(automation).each do |recipient|
      case automation.channel_type_jabvox
      when 'whatsapp_template' then send_via_template(automation, recipient)
      when 'email' then send_via_email(automation, recipient)
      when 'sms' then send_via_sms(automation, recipient)
      end
    rescue StandardError => e
      Rails.logger.error("[TaskAutomation] id=#{automation.id} recipient=#{recipient.label} error=#{e.message}")
    end
  end

  # Lista de destinatarios según recipients_jabvox, deduplicada por email/teléfono/contacto.
  def resolve_recipients(automation)
    list = []
    kinds = automation.recipient_kinds
    list << lead_recipient if kinds.include?('lead')
    list.concat(assignee_recipients(automation)) if kinds.include?('assignees')
    list << manual_recipient(automation) if kinds.include?('manual')
    list.compact.uniq { |r| [r.email.to_s.downcase, r.phone.to_s, r.contact&.id] }.reject(&:empty_target?)
  end

  def lead_recipient
    return nil if @contact.nil?

    Recipient.new(label: @contact.name, email: @contact.email,
                  phone: @contact.phone_number, contact: @contact)
  end

  # Un responsable es un User (agente): tiene email pero NO teléfono ni contacto. Para
  # WhatsApp/SMS se usa el contacto mapeado en la automatización; para email, su correo.
  def assignee_recipients(automation)
    @task.assignees.map do |user|
      mapped = automation.assignee_contact_for(user.id)
      Recipient.new(label: user.name, email: user.email,
                    phone: mapped&.phone_number, contact: mapped)
    end
  end

  def manual_recipient(automation)
    Recipient.new(
      label: automation.manual_email_jabvox.presence || automation.manual_phone_jabvox,
      email: automation.manual_email_jabvox, phone: automation.manual_phone_jabvox, contact: nil
    )
  end

  # Plantilla aprobada de WhatsApp. El texto libre solo sale dentro de la ventana de 24h y
  # una automatización de tiempo dispara justo cuando la tarea lleva rato quieta: fuera de
  # esa ventana. Las variables salen del contacto, de la tarea o de campos personalizados,
  # según lo que se haya configurado.
  def send_via_template(automation, recipient)
    inbox = automation.inbox
    return if inbox.blank? || automation.template_name_jabvox.blank?

    # WhatsApp necesita un contacto real. El lead ya lo trae; un responsable trae el contacto
    # mapeado; un destinatario manual solo un teléfono, del que se busca/crea el contacto.
    contact = recipient.contact || contact_from_phone(recipient.phone)
    return if contact.nil?

    conversation = find_or_create_conversation(inbox, contact)
    return unless conversation

    Messages::MessageBuilder.new(nil, conversation, {
                                   message_type: 'outgoing',
                                   content: automation.template_name_jabvox,
                                   private: false,
                                   template_params: template_params_for(automation, contact)
                                 }).perform
  end

  def template_params_for(automation, contact)
    {
      name: automation.template_name_jabvox,
      language: automation.template_language_jabvox.presence || 'es',
      category: 'UTILITY',
      processed_params: Jabvox::AutomationTemplateParamsService.new(
        mapping: automation.template_params_jabvox, contact: contact, task: @task
      ).call
    }
  end

  def send_via_email(automation, recipient)
    template = automation.email_template
    smtp_config = @account.jabvox_smtp_config
    return unless template && smtp_config && recipient.email.present?

    body = render_template(template.body, recipient)
    subject = render_template(template.subject, recipient)
    deliver_email(smtp_config, subject, body, recipient.email)
  end

  def deliver_email(smtp_config, subject, body, to)
    Jabvox::EmailSenderService.new(
      account: @account,
      config: smtp_config,
      to: to,
      subject: subject,
      html_body: body,
      source: 'task',
      user: Current.user
    ).deliver!
  end

  def send_via_sms(automation, recipient)
    provider = automation.sms_provider
    return unless provider && recipient.phone.present?

    body = render_template(automation.message_body_jabvox, recipient)
    Jabvox::SmsSenderService.new(provider).send_sms(
      phone: recipient.phone, message: body, account: @account, contact: recipient.contact
    )
  end

  # Contacto de la cuenta para un teléfono suelto (destinatario manual): se busca por el
  # número normalizado y, si no existe, se crea. nil si no hay teléfono utilizable.
  def contact_from_phone(phone)
    normalized = normalize_phone(phone)
    return nil if normalized.blank?

    @account.contacts.find_by(phone_number: normalized) ||
      @account.contacts.create!(name: normalized, phone_number: normalized)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Normaliza a E.164 best-effort: deja solo dígitos y antepone '+'. La normalización fina
  # la hace el canal.
  def normalize_phone(phone)
    digits = phone.to_s.strip
    return '' if digits.blank?
    return digits if digits.start_with?('+')

    only = digits.gsub(/\D/, '')
    only.present? ? "+#{only}" : ''
  end

  def find_or_create_conversation(inbox, contact)
    # ContactInboxBuilder genera el source_id con el formato propio de cada canal (para
    # WhatsApp, el teléfono sin '+'), que ContactInbox exige; find_or_create_by! sin él falla.
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    return nil unless contact_inbox

    contact_inbox.conversations.last || Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox
    )
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    nil
  end

  def render_template(text, recipient)
    return '' if text.blank?

    Liquid::Template.parse(text).render(template_vars(recipient))
  rescue Liquid::Error
    text
  end

  # Variables Liquid del mensaje. Los datos del destinatario salen de su contacto si lo
  # tiene (lead/responsable mapeado) o de sus campos sueltos (manual).
  def template_vars(recipient)
    contact = recipient.contact
    {
      'contact_name' => (contact&.name || recipient.label).to_s,
      'contact_email' => (contact&.email || recipient.email).to_s,
      'contact_phone' => (contact&.phone_number || recipient.phone).to_s,
      'task_title' => @task.title_jabvox.to_s,
      'stage_name' => @stage.name_jabvox.to_s,
      'board_name' => @task.board&.name_jabvox.to_s
    }
  end
end
