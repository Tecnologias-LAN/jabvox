# Creates/updates the mirror tables in the account's external database — one table
# per exportable jabvox model, with its safe columns plus the correlation ids
# (id_jabvox, id_db_externa, id_leads_db_externa). Idempotent: safe to re-run.
# The external DB is per-account, so table names are clean (no account prefix).
class Jabvox::ExternalExport::SchemaBuilderService
  # Correlation columns added to every mirror table.
  CORRELATION_COLUMNS = [
    { name: 'id_jabvox', type: 'bigint' },          # the record id in Jabvox
    { name: 'id_db_externa', type: 'text' },        # external DB row id, if linked
    { name: 'id_leads_db_externa', type: 'text' }   # external lead id, if linked
  ].freeze

  def initialize(target)
    @target = target
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
  end

  def call
    guard!
    Jabvox::ExternalExport::Catalog.exportable_models.each do |model|
      @adapter.ensure_table(
        Jabvox::ExternalExport::Catalog.table_name_for(model),
        columns_for(model)
      )
    end
    @target.update!(schema_built_at_jabvox: Time.current)
  end

  private

  def guard!
    result = Jabvox::Analytics::HostGuardService.new(
      host: @target.host_jabvox, port: @target.effective_port,
      allow_private: @target.allow_private_network_jabvox
    ).call
    raise Jabvox::ExternalExport::WriteAdapter::ConnectionError, result.reason unless result.allowed?
  end

  # Safe columns of the model (types from the schema) + correlation columns.
  def columns_for(model)
    cols = Jabvox::ExternalExport::Catalog.safe_columns(model).map do |name|
      { name: name, type: model.columns_hash[name]&.type || :text }
    end
    (cols + CORRELATION_COLUMNS).uniq { |c| c[:name] }
  end
end
