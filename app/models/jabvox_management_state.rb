# == Schema Information
#
# Table name: jabvox_management_states
#
#  id                       :bigint           not null, primary key
#  advisory_jabvox          :boolean          default(FALSE), not null
#  color_jabvox             :string           default("#6366f1"), not null
#  contact_jabvox           :boolean          default(FALSE), not null
#  effective_contact_jabvox :boolean          default(FALSE), not null
#  is_active_jabvox         :boolean          default(TRUE), not null
#  managed_jabvox           :boolean          default(TRUE), not null
#  name_jabvox              :string           default(""), not null
#  note_mode                :string           default("optional"), not null
#  position_jabvox          :integer          default(0), not null
#  positivity_level_jabvox  :integer          default(0), not null
#  service_type_jabvox      :string           default("No"), not null
#  state_group_jabvox       :string           default(""), not null
#  usage_info_jabvox        :text             default(""), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  idx_jabvox_mgmt_states_on_account_and_group   (account_id,state_group_jabvox)
#  index_jabvox_management_states_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxManagementState < ApplicationRecord
  self.table_name = 'jabvox_management_states'

  NOTE_MODES = %w[required optional hidden].freeze

  # "Es servicio" — suggested options for the UI select. Stored as a plain
  # string so an import can bring a new service name without a code change.
  SERVICE_TYPES = [
    'No',
    'Asesoría 1:1',
    'Asesoría Express',
    'Asesoria Grupal',
    'Toma de pedido',
    'Recordatorio de fechas',
    'Rechazos',
    'Atencion NE WA',
    'Llamada digital'
  ].freeze

  belongs_to :account
  has_many :questions, -> { order(:position) }, class_name: 'JabvoxManagementQuestion',
                                                foreign_key: :jabvox_management_state_id, dependent: :destroy, inverse_of: :management_state
  # Captured answers keep their history detached when the state is deleted
  # (the FK is nullable and has no ON DELETE), so deletion never fails.
  has_many :answers, class_name: 'JabvoxManagementAnswer', dependent: :nullify, inverse_of: false

  accepts_nested_attributes_for :questions, allow_destroy: true

  # The same substate name may exist under different groups (e.g. "Toma de
  # pedido" under both Llamada and Whatsapp), so uniqueness is per group.
  validates :name_jabvox, presence: true, uniqueness: { scope: [:account_id, :state_group_jabvox] }
  validates :position_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :note_mode, inclusion: { in: NOTE_MODES }
  validates :state_group_jabvox, length: { maximum: 150 }
  validates :service_type_jabvox, presence: true, length: { maximum: 100 }
  validates :positivity_level_jabvox,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(is_active_jabvox: true) }
  scope :ordered, -> { order(:state_group_jabvox, :position_jabvox, :name_jabvox) }
end
