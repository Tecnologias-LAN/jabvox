# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_calendar_event_participants
#
#  id                                 :bigint           not null, primary key
#  note                               :text
#  response_status                    :integer          default("pending"), not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  jabvox_calendar_event_id           :bigint           not null
#  jabvox_calendar_external_person_id :bigint
#  user_id                            :bigint
#
# Indexes
#
#  idx_calendar_participants_on_event                   (jabvox_calendar_event_id)
#  idx_calendar_participants_on_external_person         (jabvox_calendar_external_person_id)
#  index_jabvox_calendar_event_participants_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_calendar_event_id => jabvox_calendar_events.id)
#  fk_rails_...  (jabvox_calendar_external_person_id => jabvox_calendar_external_people.id)
#  fk_rails_...  (user_id => users.id)
#

# A participant of a calendar event. It is EITHER a team member (user) OR an
# external person, never both. The `note` is the message attached to that
# participant when the event is created/updated.
class JabvoxCalendarEventParticipant < ApplicationRecord
  belongs_to :jabvox_calendar_event
  belongs_to :user, optional: true
  belongs_to :external_person,
             class_name: 'JabvoxCalendarExternalPerson',
             foreign_key: :jabvox_calendar_external_person_id,
             optional: true,
             inverse_of: :jabvox_calendar_event_participants

  enum :response_status, { pending: 0, accepted: 1, declined: 2 }

  validate :user_or_external_person_present

  def team_member?
    user_id.present?
  end

  def display_name
    team_member? ? user&.available_name : external_person&.name
  end

  def email
    team_member? ? user&.email : external_person&.email
  end

  private

  def user_or_external_person_present
    return if user_id.present? ^ jabvox_calendar_external_person_id.present?

    errors.add(:base, 'participant must be either a team member or an external person')
  end
end
