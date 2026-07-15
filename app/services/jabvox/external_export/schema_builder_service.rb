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
    Jabvox::ExternalExport.guard!(@target)
  end

  # Safe columns of the model (types from the schema) + correlation columns.
  # Enum columns are stored as TEXT: ActiveRecord reports them as :integer but
  # the exported value is the human-readable enum string (e.g. "appointment"),
  # which would fail to insert into a BIGINT column.
  def columns_for(model)
    enums = model.defined_enums.keys
    cols = Jabvox::ExternalExport::Catalog.safe_columns(model).map do |name|
      type = enums.include?(name) ? :text : (model.columns_hash[name]&.type || :text)
      { name: name, type: type }
    end
    (cols + CORRELATION_COLUMNS).uniq { |c| c[:name] }
  end
end
