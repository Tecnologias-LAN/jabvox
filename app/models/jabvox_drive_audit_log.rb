# frozen_string_literal: true

# Bitácora de auditoría del Drive (append-only): registra QUIÉN hizo QUÉ sobre cada
# archivo/carpeta. Se escribe vía Jabvox::Drive::AuditService. Los metadatos están
# saneados aguas arriba (nunca contenido de archivos, tokens ni URLs firmadas).
#
# == Schema Information
#
# Table name: jabvox_drive_audit_logs
#
#  id             :bigint           not null, primary key
#  action         :string           not null
#  auditable_type :string
#  ip_address     :string
#  metadata       :jsonb            not null
#  result         :string           default("success"), not null
#  user_agent     :string
#  created_at     :datetime         not null
#  account_id     :bigint           not null
#  auditable_id   :bigint
#  user_id        :bigint
#
# Indexes
#
#  idx_drive_audit_auditable                                   (account_id,auditable_type,auditable_id)
#  index_jabvox_drive_audit_logs_on_account_id                 (account_id)
#  index_jabvox_drive_audit_logs_on_account_id_and_action      (account_id,action)
#  index_jabvox_drive_audit_logs_on_account_id_and_created_at  (account_id,created_at)
#  index_jabvox_drive_audit_logs_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxDriveAuditLog < ApplicationRecord
  # Append-only: sin updated_at.
  self.record_timestamps = false

  ACTIONS = %w[
    upload download rename move delete restore trash purge
    create_folder rename_folder move_folder delete_folder
    overflow promote regularize reconcile
  ].freeze
  RESULTS = %w[success failure rejected].freeze

  belongs_to :account
  belongs_to :user, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :result, inclusion: { in: RESULTS }

  before_validation :stamp_created_at, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }
  scope :for_auditable, ->(type, id) { where(auditable_type: type, auditable_id: id) }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
