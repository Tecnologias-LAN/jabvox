# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_calendar_events
#
#  id                  :bigint           not null, primary key
#  all_day             :boolean          default(FALSE), not null
#  color               :string           default("#3B82F6")
#  description         :text
#  end_at              :datetime         not null
#  event_type          :integer          default("reminder"), not null
#  note                :text
#  remind_before_day   :boolean          default(FALSE), not null
#  remind_before_hour  :boolean          default(FALSE), not null
#  start_at            :datetime         not null
#  status              :integer          default("pending"), not null
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  contact_id          :bigint
#  jabvox_task_id      :bigint
#  recurrence_group_id :string
#  user_id             :bigint           not null
#
# Indexes
#
#  index_jabvox_calendar_events_on_account_id               (account_id)
#  index_jabvox_calendar_events_on_account_id_and_start_at  (account_id,start_at)
#  index_jabvox_calendar_events_on_account_id_and_user_id   (account_id,user_id)
#  index_jabvox_calendar_events_on_contact_id               (contact_id)
#  index_jabvox_calendar_events_on_jabvox_task_id           (jabvox_task_id)
#  index_jabvox_calendar_events_on_recurrence_group_id      (recurrence_group_id)
#  index_jabvox_calendar_events_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_jabvox_calendar_events_contact  (contact_id => contacts.id)
#  fk_rails_...                       (account_id => accounts.id)
#  fk_rails_...                       (jabvox_task_id => jabvox_tasks.id)
#  fk_rails_...                       (user_id => users.id)
#

class JabvoxCalendarEvent < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :contact, optional: true
  belongs_to :jabvox_task, class_name: 'JabvoxTask', optional: true, inverse_of: :calendar_events
  has_many :jabvox_calendar_event_reminders, dependent: :destroy
  has_many :jabvox_calendar_event_participants, dependent: :destroy
  has_many :participant_users, through: :jabvox_calendar_event_participants, source: :user
  has_many :participant_external_people, through: :jabvox_calendar_event_participants, source: :external_person

  enum :event_type, { reminder: 0, appointment: 1, task: 2 }
  enum :status, { pending: 0, done: 1, cancelled: 2 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :start_at, presence: true
  validates :end_at, presence: true
  validate :end_after_start

  scope :ordered, -> { order(start_at: :asc) }
  scope :for_range, ->(from, to) { where(start_at: from..to) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  # Events the given user owns OR is a participant of (used for the "my calendar" filter).
  scope :visible_to_user, lambda { |user_id|
    left_joins(:jabvox_calendar_event_participants)
      .where('jabvox_calendar_events.user_id = :uid OR jabvox_calendar_event_participants.user_id = :uid', uid: user_id)
      .distinct
  }

  private

  def end_after_start
    return unless start_at && end_at && !all_day

    errors.add(:end_at, 'must be after start time') if end_at <= start_at
  end
end
