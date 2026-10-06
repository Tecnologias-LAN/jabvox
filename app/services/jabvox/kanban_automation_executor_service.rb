class Jabvox::KanbanAutomationExecutorService
  def initialize(conversation_stage)
    @cs = conversation_stage
    @account = conversation_stage.account
    @stage = conversation_stage.jabvox_kanban_stage
    @contact = resolve_contact
  end

  def perform
    return if @contact.nil?

    @stage.jabvox_kanban_stage_automations.active.where(automation_type: 'send_message').each do |automation|
      execute(automation)
    rescue StandardError => e
      Rails.logger.error("[KanbanAutomation] id=#{automation.id} error=#{e.message}")
    end
  end

  private

  def resolve_contact
    if @cs.conversation_id.present?
      @cs.conversation&.contact
    elsif @cs.contact_id.present?
      @cs.contact
    end
  end

  def execute(automation)
    case automation.channel_type
    when 'whatsapp_template' then send_via_template(automation)
    when 'email'   then send_via_email(automation)
    when 'sms'     then send_via_sms(automation)
    end
  end

  # Envía una plantilla aprobada de WhatsApp. El texto libre solo sale dentro de la ventana
  # de 24h; una automatización dispara justamente cuando la tarjeta lleva tiempo quieta,
  # o sea casi siempre fuera de esa ventana, así que la plantilla es el único envío fiable.
  def send_via_template(automation)
    inbox = automation.inbox
    return if inbox.blank? || automation.template_name_jabvox.blank?

    conversation = find_or_create_conversation(inbox)
    return unless conversation

    Messages::MessageBuilder.new(nil, conversation, {
                                   message_type: 'outgoing',
                                   content: automation.template_name_jabvox,
                                   private: false,
                                   template_params: template_params_for(automation)
                                 }).perform
  end

  def template_params_for(automation)
    {
      name: automation.template_name_jabvox,
      language: automation.template_language_jabvox.presence || 'es',
      category: 'UTILITY',
      processed_params: Jabvox::AutomationTemplateParamsService.new(
        mapping: automation.template_params_jabvox, contact: @contact, stage: @stage
      ).call
    }
  end

  def send_via_email(automation)
    template = automation.jabvox_email_template
    smtp_config = @account.jabvox_smtp_config
    return unless template && smtp_config && @contact.email.present?

    body = render_template(template.body)
    subject = render_template(template.subject)

    Jabvox::EmailSenderService.new(
      account: @account,
      config: smtp_config,
      to: @contact.email,
      subject: subject,
      html_body: body,
      source: 'kanban',
      user: Current.user
    ).deliver!
  end

  def send_via_sms(automation)
    provider = automation.jabvox_sms_provider
    return unless provider && @contact.phone_number.present?

    body = render_template(automation.message_body)
    Jabvox::SmsSendService.new(provider: provider, phone: @contact.phone_number, message: body).perform
  end

  def find_or_create_conversation(inbox)
    return @cs.conversation if @cs.conversation&.inbox_id == inbox.id

    contact_inbox = ContactInbox.find_or_create_by!(contact: @contact, inbox: inbox)
    contact_inbox.conversations.last || build_new_conversation(contact_inbox, inbox)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def build_new_conversation(contact_inbox, inbox)
    Conversation.create!(
      account: @account,
      inbox: inbox,
      contact: @contact,
      contact_inbox: contact_inbox
    )
  end

  def render_template(text)
    return '' if text.blank?

    vars = {
      'contact_name' => @contact.name.to_s,
      'contact_email' => @contact.email.to_s,
      'contact_phone' => @contact.phone_number.to_s,
      'stage_name' => @stage.name_jabvox.to_s,
      'funnel_name' => @stage.jabvox_kanban_funnel&.name_jabvox.to_s
    }
    Liquid::Template.parse(text).render(vars)
  rescue Liquid::Error
    text
  end
end
