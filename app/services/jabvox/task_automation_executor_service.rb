# Runs the automations configured on the stage a task just entered: send a message to the
# lead's contact (inbox/email/sms) and/or POST a secure webhook. Mirrors the kanban executor;
# time-based moves are handled separately by the scheduled time-automations service.
class Jabvox::TaskAutomationExecutorService
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

  def send_message(automation)
    return if @contact.nil?

    case automation.channel_type_jabvox
    when 'inbox' then send_via_inbox(automation)
    when 'email' then send_via_email(automation)
    when 'sms' then send_via_sms(automation)
    end
  end

  def send_via_inbox(automation)
    inbox = automation.inbox
    return unless inbox

    conversation = find_or_create_conversation(inbox)
    return unless conversation

    Messages::MessageBuilder.new(nil, conversation, {
                                   message_type: 'outgoing',
                                   content: render_template(automation.message_body_jabvox),
                                   private: false
                                 }).perform
  end

  def send_via_email(automation)
    template = automation.email_template
    smtp_config = @account.jabvox_smtp_config
    return unless template && smtp_config && @contact.email.present?

    body = render_template(template.body)
    subject = render_template(template.subject)
    deliver_email(smtp_config, subject, body)
  end

  def deliver_email(smtp_config, subject, body)
    Jabvox::EmailSenderService.new(
      account: @account,
      config: smtp_config,
      to: @contact.email,
      subject: subject,
      html_body: body,
      source: 'task',
      user: Current.user
    ).deliver!
  end

  def send_via_sms(automation)
    provider = automation.sms_provider
    return unless provider && @contact.phone_number.present?

    body = render_template(automation.message_body_jabvox)
    Jabvox::SmsSenderService.new(provider).send_sms(
      phone: @contact.phone_number, message: body, account: @account, contact: @contact
    )
  end

  def find_or_create_conversation(inbox)
    contact_inbox = ContactInbox.find_or_create_by!(contact: @contact, inbox: inbox)
    contact_inbox.conversations.last || Conversation.create!(
      account: @account, inbox: inbox, contact: @contact, contact_inbox: contact_inbox
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def render_template(text)
    return '' if text.blank?

    vars = {
      'contact_name' => @contact&.name.to_s,
      'contact_email' => @contact&.email.to_s,
      'contact_phone' => @contact&.phone_number.to_s,
      'task_title' => @task.title_jabvox.to_s,
      'stage_name' => @stage.name_jabvox.to_s,
      'board_name' => @task.board&.name_jabvox.to_s
    }
    Liquid::Template.parse(text).render(vars)
  rescue Liquid::Error
    text
  end
end
