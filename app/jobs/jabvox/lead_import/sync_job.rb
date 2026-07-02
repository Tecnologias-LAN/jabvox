# Runs a lead-source sync off the request cycle. Status/result land on the source
# row (last_sync_result_jabvox), which the UI polls.
class Jabvox::LeadImport::SyncJob < ApplicationJob
  queue_as :default

  def perform(lead_source_id)
    source = JabvoxLeadSource.find_by(id: lead_source_id)
    return unless source
    return unless source.account.feature_enabled?('jabvox_lead_import')

    source.update!(status_jabvox: 'syncing')
    Jabvox::LeadImport::SyncService.new(source).call
    source.update!(status_jabvox: 'ok')
  rescue StandardError => e
    Rails.logger.error("[LeadImport::Sync] source=#{lead_source_id} error=#{e.message}")
    source&.update(status_jabvox: 'error',
                   last_sync_result_jabvox: { error: e.message, at: Time.current.iso8601 })
  end
end
