# Entrada de la bitácora de auditoría de un ticket: registra quién (user_id, null si
# el sistema), qué acción, el valor anterior→nuevo y metadata. Se escribe desde el
# concern TicketLifecycle en cada transición.
# == Schema Information
#
# Table name: jabvox_ticket_activities
#
#  id                :bigint           not null, primary key
#  action_jabvox     :string           not null
#  from_value_jabvox :string
#  metadata_jabvox   :jsonb            not null
#  to_value_jabvox   :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  ticket_id         :integer          not null
#  user_id           :integer
#
# Indexes
#
#  idx_ticket_activities_ticket  (ticket_id)
#
class JabvoxTicketActivity < ApplicationRecord
  self.table_name = 'jabvox_ticket_activities'

  belongs_to :ticket, class_name: 'JabvoxTicket', inverse_of: :activities
  belongs_to :user, class_name: 'User', optional: true

  validates :action_jabvox, presence: true

  scope :chronological, -> { order(created_at: :asc) }
end
