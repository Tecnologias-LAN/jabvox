# Permanently deletes trashed leads whose retention window (30 days) has passed.
# Runs daily via the scheduler. Restored entries are ignored (they leave the trash).
class Jabvox::LeadImport::PurgeTrashJob < ApplicationJob
  queue_as :jabvox_lead_import

  def perform
    JabvoxDeletedLead.expired.in_batches(of: 500) do |batch|
      batch.delete_all
    end
  end
end
