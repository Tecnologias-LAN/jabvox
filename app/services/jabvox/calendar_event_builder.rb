# frozen_string_literal: true

# Builds one or more calendar events in a single batch.
#
# The user can define multiple time slots for the same logical appointment
# (e.g. Mon 3-4pm, Tue 5-8pm, Wed 6-9pm). Each slot becomes its own
# JabvoxCalendarEvent, all sharing a recurrence_group_id so they can later be
# edited/deleted together. Every event gets the same participants (team users
# and/or external people), and each participant carries the event's note.
#
# Usage:
#   Jabvox::CalendarEventBuilder.new(account:, user:, attributes:, slots:, participants:).perform!
#
#   slots:        [{ start_at:, end_at:, all_day: }, ...]   (at least one)
#   participants: [{ user_id: 1 }, { external_person_id: 4 }, ...]
module Jabvox
  class CalendarEventBuilder
    def initialize(account:, user:, attributes:, slots:, participants: [])
      @account = account
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @slots = Array(slots)
      @participants = Array(participants)
    end

    def perform!
      group_id = @slots.size > 1 ? SecureRandom.uuid : nil

      ActiveRecord::Base.transaction do
        @slots.map { |slot| build_event(slot, group_id) }
      end
    end

    private

    def build_event(slot, group_id)
      event = @account.jabvox_calendar_events.new(@attributes)
      event.user = @user
      event.recurrence_group_id = group_id
      event.start_at = slot[:start_at]
      event.end_at = slot[:end_at]
      event.all_day = slot[:all_day] unless slot[:all_day].nil?
      event.save!

      attach_participants(event)
      event
    end

    def attach_participants(event)
      @participants.each do |participant|
        attrs = participant.to_h.symbolize_keys
        event.jabvox_calendar_event_participants.create!(
          user_id: attrs[:user_id],
          jabvox_calendar_external_person_id: attrs[:external_person_id],
          note: attrs[:note].presence || event.note
        )
      end
    end
  end
end
