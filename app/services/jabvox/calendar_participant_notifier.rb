# frozen_string_literal: true

# Emails the event's auto-note to its external participants (those with an email).
# Team participants are not emailed here — they see the event in-app.
# Reuses the account's configured SMTP, same as Jabvox::CalendarReminderService.
module Jabvox
  class CalendarParticipantNotifier
    def initialize(events:, account:)
      @events = Array(events)
      @account = account
      @smtp = account.jabvox_smtp_config
    end

    def perform
      return if @smtp.blank? || @smtp.from_email.blank?

      @events.each { |event| notify_event(event) }
    end

    private

    def notify_event(event)
      event.jabvox_calendar_event_participants.includes(:external_person).each do |participant|
        next if participant.team_member?

        email = participant.email
        next if email.blank?

        deliver(event, participant, email)
      rescue StandardError => e
        Rails.logger.error("[CalendarNotifier] event=#{event.id} participant=#{participant.id} error=#{e.message}")
      end
    end

    def deliver(event, participant, email)
      smtp = @smtp
      subject = "#{I18n.t('jabvox.calendar.invite_subject')}: #{event.title}"
      body = invite_html(event, participant)

      Jabvox::EmailSenderService.new(
        account: @account,
        config: smtp,
        to: email,
        subject: subject,
        html_body: body,
        source: 'calendar',
        user: nil
      ).deliver!
    end

    def invite_html(event, participant)
      time_str = "#{event.start_at.strftime('%Y-%m-%d %H:%M')} – #{event.end_at.strftime('%H:%M')}"
      note = participant.note.presence || event.note
      <<~HTML
        <p>#{I18n.t('jabvox.calendar.reminder_greeting', name: participant.display_name)},</p>
        <p>#{I18n.t('jabvox.calendar.invite_body')}</p>
        <h2>#{event.title}</h2>
        <p><strong>#{I18n.t('jabvox.calendar.reminder_time')}:</strong> #{time_str}</p>
        #{"<p>#{event.description}</p>" if event.description.present?}
        #{"<p><strong>#{I18n.t('jabvox.calendar.invite_note')}:</strong> #{note}</p>" if note.present?}
      HTML
    end
  end
end
