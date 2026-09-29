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

  # Lead custom fields are exploded into one column each, so the opaque jsonb blob
  # itself is never mirrored as a column.
  LEAD_JSONB_COLUMN = 'custom_fields_jabvox'.freeze

  def initialize(target)
    @target = target
    @account = target.account
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
    @lead_custom = Jabvox::ExternalExport::LeadCustomColumns.new(@account)
  end

  def call
    guard!
    models = Jabvox::ExternalExport::Catalog.exportable_models(
      @account, selected_groups: @target.selected_modules
    )
    models.each do |model|
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
  #
  # En Contact (y en JabvoxLead mientras exista) la columna jsonb opaca
  # custom_fields_jabvox se sustituye por una columna real por cada campo personalizado
  # definido (seccion_c, alias_c…), que es lo que el cliente puede consultar desde su BD.
  def columns_for(model)
    enums = model.defined_enums.keys
    cols = physical_columns(model).map do |name|
      type = enums.include?(name) ? :text : (model.columns_hash[name]&.type || :text)
      { name: name, type: type }
    end
    cols += @lead_custom.column_defs if custom_fields_model?(model)
    cols += Jabvox::ExternalExport::DerivedColumns.defs_for(model)
    (cols + CORRELATION_COLUMNS).uniq { |c| c[:name] }
  end

  # Columnas seguras menos el jsonb (que se explota en una columna por campo).
  def physical_columns(model)
    names = Jabvox::ExternalExport::Catalog.safe_columns(model)
    return names unless custom_fields_model?(model)

    names - [LEAD_JSONB_COLUMN]
  end

  # Modelos que llevan campos personalizados inline.
  def custom_fields_model?(model)
    model == Contact
  end
end
