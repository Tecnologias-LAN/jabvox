# Mirrors one record to the account's external DB, off the request cycle. Retries
# with backoff if the external DB is temporarily unreachable so nothing is lost;
# after exhausting retries it records a sanitized error and gives up (never blocks
# the app, never surfaces credentials). Every state transition is written to the
# sync-log history (queued / exported / failed) for the settings screen.
class Jabvox::ExternalExport::WriteJob < ApplicationJob
  # Dedicated queue so real-time mirroring isn't starved behind the huge
  # critical/high/default backlogs (Sidekiq processes queues in strict priority
  # order). Sits just under the interactive queues but ahead of bulk/low work.
  queue_as :jabvox_export

  MAX_ATTEMPTS = 5

  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: MAX_ATTEMPTS

  discard_on ActiveJob::DeserializationError # record was deleted meanwhile

  def perform(account_id, model_name, record_id)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target

    klass = model_name.safe_constantize
    return unless klass

    # Normalize STI subclasses (SuperAdmin/AgentBot -> User) to the base class the
    # catalog knows about, so real-time mirrors of subclassed records still match.
    model = klass.respond_to?(:base_class) ? klass.base_class : klass

    # Respect module gating AND the customer's selected export groups: only mirror
    # models the account has enabled and chose to export.
    allowed = Jabvox::ExternalExport::Catalog.exportable_models(
      account, selected_groups: target.selected_modules
    )
    return unless allowed.include?(model)

    # Account-scoped lookup (handles models without a direct account_id column).
    record = Jabvox::ExternalExport::Catalog.account_scope(model, account_id).find_by(id: record_id)
    return unless record

    export!(target, model.name, record_id, record)
  end

  private

  def export!(target, model_name, record_id, record)
    Jabvox::ExternalExport::RowExporterService.new(target).export(record)
    target.update_columns(last_export_at_jabvox: Time.current, last_error_jabvox: nil) # rubocop:disable Rails/SkipsModelValidations
    log_status(target, model_name, record_id, 'exported')
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError => e
    # Retryable: mark queued (still trying) unless this was the final attempt.
    if final_attempt?
      log_status(target, model_name, record_id, 'failed', error: e.message)
      target.update_columns(last_error_jabvox: 'No se pudo conectar a la base de datos externa') # rubocop:disable Rails/SkipsModelValidations
    else
      log_status(target, model_name, record_id, 'queued', error: e.message)
    end
    raise # let retry_on handle backoff/attempts
  rescue StandardError => e
    Rails.logger.error("[ExternalExport::Write] #{model_name}##{record_id} #{e.class}: #{e.message}")
    log_status(target, model_name, record_id, 'failed', error: e.message)
    target.update_columns(last_error_jabvox: 'Error al exportar un registro') # rubocop:disable Rails/SkipsModelValidations
  end

  def final_attempt?
    executions >= MAX_ATTEMPTS
  end

  def log_status(target, model_name, record_id, status, error: nil)
    JabvoxExportSyncLog.record!(
      target: target, model_name: model_name, record_id: record_id,
      status: status, operation: 'realtime', error: error
    )
  end
end
