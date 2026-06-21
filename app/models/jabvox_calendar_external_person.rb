# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_calendar_external_people
#
#  id           :bigint           not null, primary key
#  color        :string           default("#0EA5E9")
#  email        :string
#  name         :string           not null
#  notes        :text
#  phone_number :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_jabvox_calendar_external_people_on_account_id            (account_id)
#  index_jabvox_calendar_external_people_on_account_id_and_email  (account_id,email)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#

class JabvoxCalendarExternalPerson < ApplicationRecord
  belongs_to :account
  has_many :jabvox_calendar_event_participants,
           foreign_key: :jabvox_calendar_external_person_id,
           dependent: :destroy,
           inverse_of: :external_person
  has_many :jabvox_calendar_events, through: :jabvox_calendar_event_participants

  validates :name, presence: true, length: { maximum: 255 }
  validates :email, length: { maximum: 255 }, allow_blank: true

  scope :ordered, -> { order(name: :asc) }
end
