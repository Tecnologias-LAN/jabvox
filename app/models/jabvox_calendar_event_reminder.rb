# == Schema Information
#
# Table name: jabvox_calendar_event_reminders
#
#  id                       :bigint           not null, primary key
#  minutes_before           :integer          not null
#  sent_at                  :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  jabvox_calendar_event_id :bigint           not null
#
# Indexes
#
#  idx_on_jabvox_calendar_event_id_8c61b31913  (jabvox_calendar_event_id)
#  index_calendar_reminders_event_minutes      (jabvox_calendar_event_id,minutes_before) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_calendar_event_id => jabvox_calendar_events.id)
#
class JabvoxCalendarEventReminder < ApplicationRecord
  belongs_to :jabvox_calendar_event

  validates :minutes_before, numericality: { only_integer: true, greater_than: 0 }
  validates :minutes_before, uniqueness: { scope: :jabvox_calendar_event_id }
end
