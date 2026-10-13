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
      .includes(:contact, :participant_users, :user)
      .find_each { |event| send_reminder(event, minutes_before, smtp) }
  end

  def send_reminder(event, minutes_before, smtp)
    deliver(event, minutes_before, smtp) if event.contact&.email.present?
    notify_users(event, minutes_before)
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
    body    = reminder_html(event, contact, label, smtp.account)

    Jabvox::EmailSenderService.new(
      account: smtp.account,
      config: smtp,
      to: contact.email,
      subject: subject,
      html_body: body,
      source: 'calendar',
      user: nil
    ).deliver!
  end

  def notify_users(event, minutes_before)
    label = minutes_label(minutes_before)
    ([event.user] + event.participant_users.to_a).compact.uniq.each do |user|
      Jabvox::ModuleNotificationService.create!(
        account: event.account,
        user: user,
        type: :jabvox_calendar_event_reminder,
        actor: event,
        title: event.title,
        body: label,
        path: "/app/accounts/#{event.account_id}/jabvox/calendar"
      )
    end
  end

  # La hora del recordatorio va en la zona de la cuenta, no en UTC. Antes se formateaba
  # el instante crudo, así que a una cuenta en Colombia el aviso le llegaba con cinco
  # horas de más. Sin zona configurada se mantiene el comportamiento anterior.
  def local_time(instant, account)
    zone = ActiveSupport::TimeZone[account.reporting_timezone.to_s]
    (zone ? instant.in_time_zone(zone) : instant).strftime('%Y-%m-%d %H:%M')
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

  def reminder_html(event, contact, label, account)
    time_str = local_time(event.start_at, account)
    <<~HTML
      <p>#{I18n.t('jabvox.calendar.reminder_greeting', name: contact.name)},</p>
      <p>#{label}</p>
      <h2>#{event.title}</h2>
      <p><strong>#{I18n.t('jabvox.calendar.reminder_time')}:</strong> #{time_str}</p>
      #{"<p>#{event.description}</p>" if event.description.present?}
    HTML
  end
end
