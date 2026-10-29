# frozen_string_literal: true

# Barrido de la PAPELERA del jabvox-drive: elimina DEFINITIVAMENTE (purga) los
# archivos que llevan más de TRASH_RETENTION_DAYS (7) días en la papelera.
#
# Al purgar: se borra el objeto físico de MinIO, se libera la cuota y se audita
# ('purge', actor=sistema). Hasta ese momento el archivo NO se pierde y sigue
# ocupando espacio (se puede restaurar). Idempotente y por cuenta (aislado): un
# fallo en una cuenta no detiene las demás.
#
# Programado en config/schedule.yml (una vez al día), cola jabvox_drive.
class Jabvox::Drive::TrashSweeperJob < ApplicationJob
  queue_as :jabvox_drive

  # Despachado por sidekiq-cron: sin reintentos (corre a diario) y alineado con
  # sidekiq-cron para que lo encole como ActiveJob (evita `undefined method 'jid='`).
  sidekiq_options retry: 0

  BATCH = 200

  def perform
    JabvoxDriveStorageAccount.find_each do |sa|
      sweep_account(sa.account_id)
    rescue StandardError => e
      Rails.logger.error("[jabvox-drive] trash sweep account_id=#{sa.account_id}: #{e.class}: #{e.message}")
    end
  end

  private

  def sweep_account(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    service = Jabvox::Drive::FileService.new(account)
    audit = Jabvox::Drive::AuditService.new(account)

    account.jabvox_drive_files
           .trash_older_than(JabvoxDriveFile::TRASH_RETENTION_DAYS)
           .limit(BATCH).find_each do |file|
      service.purge!(file, actor: nil)
      audit.log(action: 'purge', actor: nil, auditable: file,
                metadata: { filename: file.filename, bytes: file.byte_size, auto: true })
    rescue StandardError => e
      # No se detiene el barrido por un archivo problemático.
      Rails.logger.error("[jabvox-drive] trash purge file_id=#{file.id}: #{e.class}")
    end
  end
end
