# Mirrors one record to the account's external DB, off the request cycle. Retries
# with backoff if the external DB is temporarily unreachable so nothing is lost;
# after exhausting retries it records a sanitized error and gives up (never blocks
# the app, never surfaces credentials).
class Jabvox::ExternalExport::WriteJob < ApplicationJob
  queue_as :low

  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: 5

  discard_on ActiveJob::DeserializationError # record was deleted meanwhile

  def perform(account_id, model_name, record_id)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target

    model = model_name.safe_constantize
    return unless model && Jabvox::ExternalExport::Catalog.exportable_models.include?(model)

    record = model.find_by(id: record_id, account_id: account_id)
    return unless record

    Jabvox::ExternalExport::RowExporterService.new(target).export(record)
    target.update_columns(last_export_at_jabvox: Time.current, last_error_jabvox: nil) # rubocop:disable Rails/SkipsModelValidations
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError
    raise # let retry_on handle it
  rescue StandardError => e
    Rails.logger.error("[ExternalExport::Write] account=#{account_id} #{model_name}##{record_id} #{e.class}: #{e.message}")
    target&.update_columns(last_error_jabvox: 'Error al exportar un registro') # rubocop:disable Rails/SkipsModelValidations
  end
end
