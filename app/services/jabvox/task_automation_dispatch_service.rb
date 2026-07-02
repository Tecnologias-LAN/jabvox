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
    @lead = @task.jabvox_lead
  end

  # Sends to every resolved recipient and returns the created run.
  def perform
    # A completed task's automations never fire, regardless of the dispatch path
    # (scheduled batch or manual "run now"). The batch already excludes done
    # tasks; this guards the direct/manual path too.
    return record_run(status: 'skipped', count: 0, detail: 'task_done') if @task.status_jabvox == 'done'

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
    # Don't advance the schedule when skipped because the task is done — leave
    # next_run_at as-is so it resumes correctly if the task is reopened.
    @automation.mark_ran! if @automation.persisted? && @task.status_jabvox != 'done'
  end

  private

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
    contact = @lead&.contact
    return [] unless contact

    [Recipient.new(label: contact.name, email: contact.email,
                   phone: contact.phone_number, contact: contact)]
  end

  def assignee_recipients
    @task.assignees.map do |u|
      Recipient.new(label: u.name, email: u.email, phone: nil, contact: nil)
    end
  end

  def lead_contact_recipients
    return [] unless @lead

    @account.jabvox_task_lead_contacts.where(jabvox_lead_id: @lead.id).map do |c|
      Recipient.new(label: c.name_jabvox, email: c.email_jabvox,
                    phone: c.phone_jabvox, contact: nil)
    end
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
    when 'inbox' then deliver_inbox(recipient)
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

  def deliver_inbox(recipient)
    contact = recipient.contact
    raise 'sin_contacto' unless contact

    inbox = @automation.inbox
    raise 'sin_inbox' unless inbox

    conversation = find_or_create_conversation(contact, inbox)
    raise 'sin_conversacion' unless conversation

    Messages::MessageBuilder.new(nil, conversation, {
                                   message_type: 'outgoing',
                                   content: render(@automation.body_jabvox),
                                   private: false
                                 }).perform
  end

  def find_or_create_conversation(contact, inbox)
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox)
    contact_inbox.conversations.last || Conversation.create!(
      account: @account, inbox: inbox, contact: contact, contact_inbox: contact_inbox
    )
  rescue ActiveRecord::RecordInvalid
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
      'lead_name' => @lead&.contact&.name.to_s
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
