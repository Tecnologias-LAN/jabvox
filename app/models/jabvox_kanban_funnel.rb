# == Schema Information
#
# Table name: jabvox_kanban_funnels
#
#  id                       :bigint           not null, primary key
#  active_jabvox            :boolean          default(TRUE), not null
#  description_jabvox       :text
#  include_own_leads_jabvox :boolean          default(FALSE), not null
#  name_jabvox              :string           not null
#  position_jabvox          :integer          default(0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_jabvox_kanban_funnels_on_account_id                  (account_id)
#  index_jabvox_kanban_funnels_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxKanbanFunnel < ApplicationRecord
  self.table_name = 'jabvox_kanban_funnels'

  belongs_to :account
  has_many :jabvox_kanban_funnel_inboxes, dependent: :destroy
  has_many :inboxes, through: :jabvox_kanban_funnel_inboxes
  has_many :jabvox_kanban_funnel_campaigns, dependent: :destroy
  has_many :jabvox_campaigns, through: :jabvox_kanban_funnel_campaigns
  has_many :jabvox_kanban_funnel_affiliates, dependent: :destroy
  has_many :jabvox_affiliates, through: :jabvox_kanban_funnel_affiliates
  has_many :jabvox_kanban_stages, -> { order(:position_jabvox) }, dependent: :destroy, inverse_of: :jabvox_kanban_funnel
  has_many :jabvox_kanban_conversation_stages, dependent: :destroy

  validates :name_jabvox,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }
  validates :position_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox, :created_at) }

  def first_stage
    jabvox_kanban_stages.order(:position_jabvox).first
  end
end
