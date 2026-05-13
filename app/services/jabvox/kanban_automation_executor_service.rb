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
    elsif @cs.jabvox_lead_id.present?
      @cs.jabvox_lead&.contact
    end
  end

  def execute(automation)
    case automation.channel_type
    when 'inbox'   then send_via_inbox(automation)
    when 'email'   then send_via_email(automation)
    when 'sms'     then send_via_sms(automation)
    end
  end

  def send_via_inbox(automation)
    inbox = automation.inbox
    return unless inbox

    conversation = find_or_create_conversation(inbox)
    return unless conversation

    body = render_template(automation.message_body)
    Messages::MessageBuilder.new(nil, conversation, {
      message_type: 'outgoing',
      content: body,
      private: false
    }).perform
  end

  def send_via_email(automation)
    template = automation.jabvox_email_template
    smtp_config = @account.jabvox_smtp_config
    return unless template && smtp_config && @contact.email.present?

    body = render_template(template.body)
    subject = render_template(template.subject)

    mail = Mail.new do
      from     "#{smtp_config.from_name} <#{smtp_config.from_email}>"
      to       @contact.email
      subject  subject
      html_part do
        content_type 'text/html; charset=UTF-8'
        body body
      end
    end

    mail.delivery_method(:smtp, smtp_config.delivery_settings)
    mail.deliver!
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
      'contact_name'  => @contact.name.to_s,
      'contact_email' => @contact.email.to_s,
      'contact_phone' => @contact.phone_number.to_s,
      'stage_name'    => @stage.name_jabvox.to_s,
      'funnel_name'   => @stage.jabvox_kanban_funnel&.name_jabvox.to_s
    }
    Liquid::Template.parse(text).render(vars)
  rescue Liquid::Error
    text
  end
end
