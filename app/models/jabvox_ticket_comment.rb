# Comentario de un ticket. Si private_jabvox es true es una NOTA INTERNA: visible
# solo para el staff y nunca notificada al solicitante.
# == Schema Information
#
# Table name: jabvox_ticket_comments
#
#  id             :bigint           not null, primary key
#  body_jabvox    :text             not null
#  private_jabvox :boolean          default(FALSE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  ticket_id      :integer          not null
#  user_id        :integer          not null
#
# Indexes
#
#  idx_ticket_comments_ticket          (ticket_id)
#  idx_ticket_comments_ticket_created  (ticket_id,created_at)
#
class JabvoxTicketComment < ApplicationRecord
  include Jabvox::TicketImageAttachable

  self.table_name = 'jabvox_ticket_comments'

  belongs_to :ticket, class_name: 'JabvoxTicket', inverse_of: :comments
  belongs_to :user, class_name: 'User'

  validates :body_jabvox, presence: true

  scope :public_comments, -> { where(private_jabvox: false) }
  scope :internal_notes, -> { where(private_jabvox: true) }

  def private?
    private_jabvox
  end
end
