class Jabvox::CalendarReminderService
  def perform
    JabvoxSmtpConfig
      .where(calendar_reminders_enabled: true)
      .find_each { |smtp| process_account(smtp) }
  end

  private

  def process_account(smtp)
    minutes_list = Array(smtp.calendar_reminder_minutes).map(&:to_i).select(&:positive?)
    return if minutes_list.empty?

    minutes_list.each { |m| send_reminders_for(smtp.account_id, m, smtp) }
  end

  def send_reminders_for(account_id, minutes_before, smtp)
    window_start = minutes_before.minutes.from_now - 30.minutes
    window_end   = minutes_before.minutes.from_now + 30.minutes

    already_sent = JabvoxCalendarEventReminder
                   .where(minutes_before: minutes_before)
                   .select(:jabvox_calendar_event_id)

    JabvoxCalendarEvent
      .where(account_id: account_id)
      .where(start_at: window_start..window_end)
      .where.not(id: already_sent)
      .where.not(contact_id: nil)
      .includes(:contact)
      .find_each { |event| send_reminder(event, minutes_before, smtp) }
  end

  def send_reminder(event, minutes_before, smtp)
    return if event.contact&.email.blank?

    deliver(event, minutes_before, smtp)
    JabvoxCalendarEventReminder.create!(
      jabvox_calendar_event: event,
      minutes_before: minutes_before,
      sent_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[CalendarReminder] event=#{event.id} error=#{e.message}")
  end

  def deliver(event, minutes_before, smtp)
    contact = event.contact
    label   = minutes_label(minutes_before)
    subject = "#{I18n.t('jabvox.calendar.reminder_subject')}: #{event.title}"
    body    = reminder_html(event, contact, label)

    mail = Mail.new do
      from    "#{smtp.from_name} <#{smtp.from_email}>"
      to      contact.email
      subject subject
      html_part do
        content_type 'text/html; charset=UTF-8'
        body body
      end
    end

    mail.delivery_method(:smtp, smtp.delivery_settings)
    mail.deliver!
  end

  def minutes_label(minutes)
    if minutes >= 1440 && (minutes % 1440).zero?
      I18n.t('jabvox.calendar.reminder_n_days', count: minutes / 1440)
    elsif minutes >= 60 && (minutes % 60).zero?
      I18n.t('jabvox.calendar.reminder_n_hours', count: minutes / 60)
    else
      I18n.t('jabvox.calendar.reminder_n_minutes', count: minutes)
    end
  end

  def reminder_html(event, contact, label)
    time_str = event.start_at.strftime('%Y-%m-%d %H:%M')
    <<~HTML
      <p>#{I18n.t('jabvox.calendar.reminder_greeting', name: contact.name)},</p>
      <p>#{label}</p>
      <h2>#{event.title}</h2>
      <p><strong>#{I18n.t('jabvox.calendar.reminder_time')}:</strong> #{time_str}</p>
      #{"<p>#{event.description}</p>" if event.description.present?}
    HTML
  end
end
