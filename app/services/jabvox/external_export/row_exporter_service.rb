# Exports a single record (any exportable jabvox model) to the account's external
# DB as a parameterized upsert keyed by id_jabvox. Strips sensitive columns and
# attaches the correlation ids. Never raises to the caller path — the job handles retries.
class Jabvox::ExternalExport::RowExporterService
  # The lead jsonb blob is exploded into per-field columns (see LeadCustomColumns);
  # it is never written as a column itself.
  LEAD_JSONB_COLUMN = 'custom_fields_jabvox'.freeze

  # resolver: an optional preloaded LeadResolver (backfill reuses
  # one so it doesn't query the contact->lead map per row). Real-time exports get
  # a per-call resolver that queries directly.
  def initialize(target, resolver: nil)
    @target = target
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
    @lead_custom = Jabvox::ExternalExport::LeadCustomColumns.new(target.account)
    resolver ||= Jabvox::ExternalExport::LeadResolver.new(target.account_id)
    @derived = Jabvox::ExternalExport::DerivedColumns.new(resolver)
  end

  # record is a jabvox model instance whose class is in the catalog.
  # Single-record path (real-time mirror): one guarded, one-connection upsert.
  #
  # Self-healing: if the write fails because a column is missing (e.g. a custom
  # field was added after the schema was last built, and a lead now carries it),
  # we ensure that table's columns and retry once — so real-time sync never gets
  # stuck on a schema drift.
  def export(record)
    return unless exportable?(record)

    guard!
    plan = row_plan(record)
    return if plan.nil?

    begin
      @adapter.upsert_row(plan[:table], plan[:values], conflict_key: plan[:key])
    rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError => e
      raise unless missing_column_error?(e)

      ensure_columns_for(record, plan)
      @adapter.upsert_row(plan[:table], plan[:values], conflict_key: plan[:key])
    end
  end

  # Batch path (backfill): write with an already-open client so a whole batch
  # reuses ONE connection. Returns true if written, false if skipped.
  def export_on(client, record)
    return false unless exportable?(record)

    plan = row_plan(record)
    return false if plan.nil?

    @adapter.upsert_row_on(client, plan[:table], plan[:values], conflict_key: plan[:key])
    true
  end

  # Public plan accessor for the batch backfill: { table:, values:, key: } or nil.
  def plan_for(record)
    return nil unless exportable?(record)

    row_plan(record)
  end

  private

  # True when the error looks like "column X does not exist" on either engine.
  def missing_column_error?(error)
    error.message.to_s.match?(/column .* does not exist|Unknown column|no column named/i)
  end

  # Ensures the mirror table has every column the current plan needs, by adding
  # the missing ones (idempotent). Used to self-heal after schema drift.
  def ensure_columns_for(record, plan)
    model = base_class_of(record)
    cols = plan[:values].keys.map do |name|
      { name: name, type: column_type_for(model, name) }
    end
    @adapter.add_missing_columns(plan[:table], cols)
  end

  # Best-effort storage type for a column name: from the model's schema, from the
  # lead custom-field defs, or text as a safe default.
  def column_type_for(model, name)
    if custom_fields_model?(model)
      cdef = @lead_custom.column_defs.find { |c| c[:name] == name }
      return cdef[:type] if cdef
    end
    col = model.columns_hash[name]
    col ? col.type : :text
  end

  # True when the record's model (normalized to its STI base class) is exportable.
  def exportable?(record)
    Jabvox::ExternalExport::Catalog.exportable_models.include?(base_class_of(record))
  end

  def base_class_of(record)
    klass = record.class
    klass.respond_to?(:base_class) ? klass.base_class : klass
  end

  # { table:, values:, key: } for the record. Single flow: mirror all safe columns
  # into our own tables, keyed by id_jabvox.
  def row_plan(record)
    table = Jabvox::ExternalExport::Catalog.table_name_for(base_class_of(record))
    create_plan(record, table)
  end

  # create mode: mirror all safe columns + correlation ids, keyed by id_jabvox.
  # For leads, the jsonb blob is replaced by one value per expanded custom column.
  # For core models (Conversation/Message) and the dialer call log we add derived
  # link columns (contact_id / jabvox_lead_id) so the CRM can join to the lead.
  def create_plan(record, table)
    values = safe_values(record)
    if custom_fields_model?(record.class)
      values.delete(LEAD_JSONB_COLUMN)
      values.merge!(@lead_custom.values_for(record))
    end
    values.merge!(@derived.for(record))
    { table: table, values: values.merge(correlation_ids(record)), key: 'id_jabvox' }
  end

  def guard!
    Jabvox::ExternalExport.guard!(@target)
  end

  # Only safe columns (sensitive ones removed by the catalog).
  def safe_values(record)
    Jabvox::ExternalExport::Catalog.safe_columns(record.class).index_with do |col|
      record[col]
    end
  end

  # id_jabvox siempre; los ids de la BD externa solo cuando el registro es un contacto
  # ligado a una fuente de importación (para que los reportes del otro lado puedan cruzar).
  def correlation_ids(record)
    ids = { 'id_jabvox' => record.id, 'id_db_externa' => nil, 'id_leads_db_externa' => nil }
    if record.is_a?(Contact)
      link = record.jabvox_lead_source_records.first
      ids['id_leads_db_externa'] = link&.external_id_jabvox
    end
    ids
  end

  # Modelos cuyos campos personalizados se explotan en columnas reales.
  def custom_fields_model?(model)
    model == Contact
  end
end
