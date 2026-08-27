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
#  parent_id                     :integer
#  responsible_id                :integer
#
# Indexes
#
#  idx_ticket_categories_account         (account_id)
#  idx_ticket_categories_account_active  (account_id,active_jabvox)
#  idx_ticket_categories_account_parent  (account_id,parent_id)
#
class JabvoxTicketCategory < ApplicationRecord
  self.table_name = 'jabvox_ticket_categories'

  belongs_to :account
  belongs_to :responsible, class_name: 'User', optional: true
  # Subtema: un tema padre opcional (self-reference). Sin parent = tema raíz.
  belongs_to :parent, class_name: 'JabvoxTicketCategory', optional: true
  has_many :children, class_name: 'JabvoxTicketCategory', foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :nullify
  has_many :tickets, class_name: 'JabvoxTicket', foreign_key: :ticket_category_id,
                     inverse_of: :category, dependent: :nullify

  enum category_type_jabvox: { incident: 0, requirement: 1, request: 2 }, _prefix: :type

  validates :name_jabvox, presence: true
  validates :sla_response_minutes_jabvox, :sla_resolution_minutes_jabvox,
            numericality: { only_integer: true, greater_than: 0 }
  validate :parent_not_self
  validate :parent_same_type

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(position_jabvox: :asc, name_jabvox: :asc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :roots, -> { where(parent_id: nil) }
  scope :subtopics, -> { where.not(parent_id: nil) }

  def subtopic?
    parent_id.present?
  end

  private

  # Un tema no puede ser su propio padre (evita el ciclo trivial; la jerarquía es de
  # un solo nivel por diseño, así que no hacen falta comprobaciones más profundas).
  def parent_not_self
    errors.add(:parent_id, 'no puede ser el mismo tema') if parent_id.present? && parent_id == id
  end

  # El subtema debe compartir el tipo (incidente/requerimiento/solicitud) del padre.
  def parent_same_type
    return if parent.nil? || parent.category_type_jabvox == category_type_jabvox

    errors.add(:parent_id, 'debe ser del mismo tipo que el subtema')
  end
end
