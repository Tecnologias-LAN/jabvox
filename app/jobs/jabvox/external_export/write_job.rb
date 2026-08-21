# LEGACY / compatibilidad de cola: el espejo en tiempo real ahora pasa por
# ExternalExport::DrainJob (Set por cuenta + drenado por lotes). Este job ya NO se
# encola desde el concern, pero se mantiene funcional para DRENAR los WriteJob que
# hayan quedado en la cola jabvox_export de una versión anterior tras el deploy.
# No borrar hasta confirmar que la cola no tiene WriteJob pendientes.
#
# Mirrors one record to the account's external DB, off the request cycle. Retries
# with backoff if the external DB is temporarily unreachable so nothing is lost;
# after exhausting retries it records a sanitized error and gives up (never blocks
# the app, never surfaces credentials).
class Jabvox::ExternalExport::WriteJob < ApplicationJob
  # Dedicated queue so real-time mirroring isn't starved behind the huge
  # critical/high/default backlogs (Sidekiq processes queues in strict priority
  # order). Sits just under the interactive queues but ahead of bulk/low work.
  queue_as :jabvox_export

  MAX_ATTEMPTS = 5
  UNREACHABLE_TTL = 60 # s; marca la BD externa como caída para el circuit-breaker

  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: MAX_ATTEMPTS

  discard_on ActiveJob::DeserializationError # record was deleted meanwhile

  # Args con deferrals opcional por compatibilidad con jobs legacy ya encolados.
  def perform(account_id, model_name, record_id, _deferrals = 0)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target

    model, record = resolve_model_and_record(account, target, model_name, record_id)
    return unless record

    export!(target, model.name, record_id, record)
  end

  private

  # Devuelve [model, record] si el registro es exportable para esta cuenta, o nil.
  def resolve_model_and_record(account, target, model_name, record_id)
    klass = model_name.safe_constantize
    return unless klass

    # Normalize STI subclasses (SuperAdmin/AgentBot -> User) to the base class.
    model = klass.respond_to?(:base_class) ? klass.base_class : klass

    allowed = Jabvox::ExternalExport::Catalog.exportable_models(account, selected_groups: target.selected_modules)
    return unless allowed.include?(model)

    record = Jabvox::ExternalExport::Catalog.account_scope(model, account.id).find_by(id: record_id)
    return unless record

    [model, record]
  end

  def export!(target, model_name, record_id, record)
    Jabvox::ExternalExport::RowExporterService.new(target).export(record)
    target.update_columns(last_export_at_jabvox: Time.current, last_error_jabvox: nil) # rubocop:disable Rails/SkipsModelValidations
    log_status(target, model_name, record_id, 'exported')
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError => e
    # La BD externa no respondió: marca para que el circuit-breaker corte el resto
    # de writes de esta cuenta y no se sature reintentando contra una BD caída.
    mark_unreachable(target.account_id)
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

  def mark_unreachable(account_id)
    Redis::Alfred.set("jabvox_export_db_unreachable_#{account_id}", Time.current.to_i, ex: UNREACHABLE_TTL)
  rescue StandardError
    nil
  end

  def log_status(target, model_name, record_id, status, error: nil)
    JabvoxExportSyncLog.record!(
      target: target, model_name: model_name, record_id: record_id,
      status: status, operation: 'realtime', error: error
    )
  end
end
