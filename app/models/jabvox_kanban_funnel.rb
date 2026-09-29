# == Schema Information
#
# Table name: jabvox_kanban_funnels
#
#  id                          :bigint           not null, primary key
#  active_jabvox               :boolean          default(TRUE), not null
#  description_jabvox          :text
#  include_own_contacts_jabvox :boolean          default(FALSE), not null
#  lifecycle_stages_jabvox     :string           default([]), not null, is an Array
#  name_jabvox                 :string           not null
#  position_jabvox             :integer          default(0), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  created_by_id               :bigint
#
# Indexes
#
#  index_jabvox_kanban_funnels_on_account_id                  (account_id)
#  index_jabvox_kanban_funnels_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_kanban_funnels_on_created_by_id               (created_by_id)
#  index_jabvox_kanban_funnels_on_lifecycle_stages_jabvox     (lifecycle_stages_jabvox) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
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

  # Cambiar las etapas del embudo retira las tarjetas que ya no le corresponden. Sin esto,
  # quitar "cliente" de un embudo dejaba dentro a los clientes ya colocados y el tablero
  # contradecía su propia configuración.
  after_commit :purge_contacts_outside_stages, on: :update, if: :saved_change_to_lifecycle_stages_jabvox?

  def first_stage
    jabvox_kanban_stages.order(:position_jabvox).first
  end

  # Solo se van los que estaban SOLO por la etapa: quien además entra por bandeja, campaña,
  # afiliado o "propios" sigue perteneciendo al embudo. Va al final, en la zona privada
  # existente: un `private` a media clase dejaba privados los métodos de debajo —entre
  # ellos `first_stage`, que el tablero llama— y la pantalla devolvía 500.
  def purge_contacts_outside_stages
    contact_ids = jabvox_kanban_conversation_stages.where.not(contact_id: nil).distinct.pluck(:contact_id)
    return if contact_ids.empty?

    account.contacts.where(id: contact_ids).find_each do |contact|
      Jabvox::KanbanLifecycleSync.new(contact).perform
    end
  rescue StandardError => e
    Rails.logger.error("[jabvox] purga del embudo #{id} falló: #{e.class}")
  end
end
