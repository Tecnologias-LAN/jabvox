# Renders a dashboard export (PDF/Excel/CSV) in the background, attaches the file via
# ActiveStorage and updates the export record's status.
class Jabvox::Analytics::ExportJob < ApplicationJob
  include Jabvox::AccountFairShare
  queue_as :jabvox_analytics

  # Fairness: una cuenta con muchos exports no acapara el worker analytics (cada export
  # se renderiza en RAM, así que además protege memoria). Override por ENV.
  fair_share_limit 3
  fair_share_env 'JABVOX_ANALYTICS_MAX_INFLIGHT_PER_ACCOUNT'

  def perform(export_id)
    export = JabvoxAnalyticsExport.find_by(id: export_id)
    return unless export
    return unless export.account.feature_enabled?('jabvox_analytics')
    # Idempotencia: no re-generar un export ya completado (reintento solapado).
    return if export.status_jabvox == 'completed'

    with_account_fair_share(export.account_id) do
      export.update!(status_jabvox: 'processing')
      output = Jabvox::Analytics::ExportService.new(export).call
      export.file.attach(io: StringIO.new(output.bytes), filename: output.filename, content_type: output.content_type)
      export.update!(status_jabvox: 'completed', file_url_jabvox: file_url(export))
    end
  rescue StandardError => e
    Rails.logger.error "[Analytics::Export] job failed for ##{export_id}: #{e.message}"
    export&.update(status_jabvox: 'failed', error_jabvox: 'No se pudo generar la exportación')
  end

  private

  def file_url(export)
    Rails.application.routes.url_helpers.rails_blob_path(export.file, only_path: true)
  rescue StandardError
    nil
  end
end
