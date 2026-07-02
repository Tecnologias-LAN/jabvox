# Mixed into every exportable jabvox model (via the initializer, driven by the
# catalog). On create/update it enqueues a lightweight mirror job — only when the
# account has the data-export module enabled and an active target. Deletes are not
# mirrored (the external DB keeps history for reporting); this is intentional.
module Jabvox::ExportableToExternalDb
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_external_export, on: %i[create update]
  end

  private

  def enqueue_external_export
    account_id = self[:account_id]
    return if account_id.blank?
    return unless Jabvox::ExternalExport.export_enabled?(account_id)

    Jabvox::ExternalExport::WriteJob.perform_later(account_id, self.class.name, id)
  rescue StandardError => e
    # Never let export bookkeeping break the primary write.
    Rails.logger.error("[ExternalExport] enqueue failed #{self.class.name}##{id}: #{e.message}")
  end
end
