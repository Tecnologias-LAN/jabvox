# frozen_string_literal: true

# Archivo canónico del Drive. Una fila por objeto FÍSICO en MinIO. Varias
# referencias internas (un adjunto que aparece en una conversación y en el Drive)
# comparten la misma fila por (account_id, sha256) para NO contar doble la cuota.
#
# status:
#   available   -> visible y descargable (bucket principal).
#   restricted  -> en bucket de excedentes (cuota llena); NO visible en vistas
#                  normales hasta regularizar.
#   pending     -> subida/ingesta en curso (aún no confirmada).
#   quarantined -> retenido por análisis/seguridad.
#
# == Schema Information
#
# Table name: jabvox_drive_files
#
#  id              :bigint           not null, primary key
#  bucket          :string           default("primary"), not null
#  byte_size       :bigint           default(0), not null
#  content_type    :string
#  deleted_at      :datetime
#  filename        :string           not null
#  metadata        :jsonb            not null
#  object_key      :string           not null
#  sha256          :string
#  status          :integer          default("available"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  created_by_id   :bigint
#  folder_id       :bigint
#  message_id      :bigint
#
# Indexes
#
#  idx_drive_files_unique_object                          (account_id,object_key) UNIQUE
#  index_jabvox_drive_files_on_account_id                 (account_id)
#  index_jabvox_drive_files_on_account_id_and_contact_id  (account_id,contact_id)
#  index_jabvox_drive_files_on_account_id_and_folder_id   (account_id,folder_id)
#  index_jabvox_drive_files_on_account_id_and_message_id  (account_id,message_id)
#  index_jabvox_drive_files_on_account_id_and_sha256      (account_id,sha256)
#  index_jabvox_drive_files_on_account_id_and_status      (account_id,status)
#  index_jabvox_drive_files_on_contact_id                 (contact_id)
#  index_jabvox_drive_files_on_conversation_id            (conversation_id)
#  index_jabvox_drive_files_on_created_by_id              (created_by_id)
#  index_jabvox_drive_files_on_folder_id                  (folder_id)
#  index_jabvox_drive_files_on_message_id                 (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (folder_id => jabvox_drive_folders.id)
#  fk_rails_...  (message_id => messages.id)
#
class JabvoxDriveFile < ApplicationRecord
  belongs_to :account
  belongs_to :folder, class_name: 'JabvoxDriveFolder', optional: true
  belongs_to :contact, optional: true
  belongs_to :message, optional: true
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :trashed_by, class_name: 'User', optional: true
  belongs_to :purged_by, class_name: 'User', optional: true

  enum status: { available: 0, restricted: 1, pending: 2, quarantined: 3 }

  validates :filename, :object_key, presence: true
  validates :object_key, uniqueness: { scope: :account_id }

  # Ciclo de vida respecto a la papelera:
  #   deleted_at nil                       -> activo (visible/kept).
  #   deleted_at set + purged_at nil       -> EN LA PAPELERA (aún ocupa cuota).
  #   purged_at set                        -> eliminado del todo (ya no ocupa).
  scope :visible, -> { where(status: :available, deleted_at: nil) }
  scope :kept, -> { where(deleted_at: nil) }
  # En la papelera: borrado lógico pero NO purgado (sigue ocupando espacio).
  scope :in_trash, -> { where.not(deleted_at: nil).where(purged_at: nil) }
  # Ocupa cuota: lo activo + lo que está en la papelera (hasta que se purgue).
  scope :occupying_quota, -> { where(purged_at: nil) }
  # En la papelera desde hace más de `days` días (candidatos a auto-purga).
  scope :trash_older_than, ->(days) { in_trash.where('deleted_at < ?', days.to_i.days.ago) }

  BUCKET_PRIMARY = 'primary'
  BUCKET_OVERFLOW = 'overflow'
  # Días que un archivo permanece en la papelera antes de purgarse automáticamente.
  TRASH_RETENTION_DAYS = 7

  def overflow?
    bucket == BUCKET_OVERFLOW
  end

  def in_trash?
    deleted_at.present? && purged_at.nil?
  end

  def purged?
    purged_at.present?
  end

  # Enviar a la papelera (reversible). NO libera cuota ni borra el objeto físico.
  def trash!(actor = nil)
    update!(deleted_at: Time.current, trashed_by: actor)
  end

  # Restaurar desde la papelera.
  def restore!
    update!(deleted_at: nil, trashed_by: nil)
  end

  # Marcar como purgado (el borrado físico y el descuento de cuota los hace el service).
  def mark_purged!(actor = nil)
    update!(purged_at: Time.current, purged_by: actor)
  end

  # Compatibilidad: soft_delete! ahora es "enviar a papelera".
  def soft_delete!(actor = nil)
    trash!(actor)
  end

  def category
    case content_type.to_s
    when %r{\Aimage/} then 'image'
    when %r{\Avideo/} then 'video'
    when %r{\Aaudio/} then 'audio'
    else 'document'
    end
  end
end
