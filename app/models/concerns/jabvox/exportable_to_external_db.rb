# Mixed into every exportable model (via the initializer, driven by the catalog).
# On create/update it enqueues a lightweight mirror job — only for accounts that
# have the data-export module enabled and an active target. Deletes are not
# mirrored (the external DB keeps history for reporting); this is intentional.
#
# Most models belong to one account (account_id column). A few reach the account
# through an association and may even belong to MANY accounts (a User via
# account_users) — those enqueue one job per exporting account.
module Jabvox::ExportableToExternalDb
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_external_export, on: %i[create update]
  end

  private

  # En vez de encolar un WriteJob por registro (avalancha + vecino ruidoso), se
  # añade el (modelo,id) al Redis Set de la cuenta (dedup = coalescing) y se
  # asegura UN drenador por cuenta. El DrainJob procesa el Set en lotes: sin
  # avalancha de jobs, sin busy-loop, y con fairness real entre cuentas.
  def enqueue_external_export
    export_account_ids.each do |account_id|
      next if account_id.blank?
      next unless Jabvox::ExternalExport.export_enabled?(account_id)

      Redis::Alfred.sadd(Jabvox::ExternalExport::DrainJob.pending_set_key(account_id), "#{self.class.name}:#{id}")
      Jabvox::ExternalExport::DrainJob.ensure_enqueued(account_id)
    end
  rescue StandardError => e
    # Never let export bookkeeping break the primary write.
    Rails.logger.error("[ExternalExport] enqueue failed #{self.class.name}##{id}: #{e.message}")
  end

  # The account(s) this record should mirror into: straight from account_id, or
  # derived for models reached through an association.
  def export_account_ids
    return [self[:account_id]] if has_attribute?(:account_id)

    case self
    when JabvoxCustomTableRow then [jabvox_custom_table&.account_id]
    when User then account_users.pluck(:account_id)
    else []
    end
  end
end
