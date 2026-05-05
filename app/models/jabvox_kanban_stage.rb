# == Schema Information
#
# Table name: jabvox_kanban_stages
#
#  id                      :bigint           not null, primary key
#  color_jabvox            :string           default("#6B7280"), not null
#  description_jabvox      :text
#  name_jabvox             :string           not null
#  position_jabvox         :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  jabvox_kanban_funnel_id :bigint           not null
#
# Indexes
#
#  index_jabvox_kanban_stages_on_account_id               (account_id)
#  index_jabvox_kanban_stages_on_jabvox_kanban_funnel_id  (jabvox_kanban_funnel_id)
#  index_jabvox_stages_funnel_position                    (jabvox_kanban_funnel_id,position_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#
class JabvoxKanbanStage < ApplicationRecord
  self.table_name = 'jabvox_kanban_stages'

  belongs_to :jabvox_kanban_funnel
  belongs_to :account
  has_many :jabvox_kanban_conversation_stages, dependent: :nullify

  validates :name_jabvox,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :jabvox_kanban_funnel_id }
  validates :position_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :color_jabvox, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: 'must be a valid hex color' }

  scope :ordered, -> { order(:position_jabvox) }

  before_validation :set_default_position, on: :create

  private

  def set_default_position
    return if position_jabvox.present?

    max = jabvox_kanban_funnel&.jabvox_kanban_stages&.maximum(:position_jabvox) || -1
    self.position_jabvox = max + 1
  end
end
