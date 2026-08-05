# Tema/categoría de tickets por cuenta: define tipo (incidente/requerimiento/
# solicitud), color, SLA de respuesta y resolución, y un responsable opcional para
# la autoasignación por categoría. Solo un manager las administra.
# == Schema Information
#
# Table name: jabvox_ticket_categories
#
#  id                            :bigint           not null, primary key
#  active_jabvox                 :boolean          default(TRUE), not null
#  category_type_jabvox          :integer          default("incident"), not null
#  color_jabvox                  :string           default("#1F93FF"), not null
#  description_jabvox            :text
#  name_jabvox                   :string           not null
#  position_jabvox               :integer          default(0), not null
#  sla_resolution_minutes_jabvox :integer          default(1440), not null
#  sla_response_minutes_jabvox   :integer          default(60), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :integer          not null
#  responsible_id                :integer
#
# Indexes
#
#  idx_ticket_categories_account         (account_id)
#  idx_ticket_categories_account_active  (account_id,active_jabvox)
#
class JabvoxTicketCategory < ApplicationRecord
  self.table_name = 'jabvox_ticket_categories'

  belongs_to :account
  belongs_to :responsible, class_name: 'User', optional: true
  has_many :tickets, class_name: 'JabvoxTicket', foreign_key: :ticket_category_id,
                     inverse_of: :category, dependent: :nullify

  enum category_type_jabvox: { incident: 0, requirement: 1, request: 2 }, _prefix: :type

  validates :name_jabvox, presence: true
  validates :sla_response_minutes_jabvox, :sla_resolution_minutes_jabvox,
            numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(position_jabvox: :asc, name_jabvox: :asc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
end
