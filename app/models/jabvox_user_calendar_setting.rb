class JabvoxUserCalendarSetting < ApplicationRecord
  belongs_to :account
  belongs_to :user

  serialize :reminder_minutes, coder: JSON

  validates :user_id, uniqueness: { scope: :account_id }
end
