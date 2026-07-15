# Exports a single record (any exportable jabvox model) to the account's external
# DB as a parameterized upsert keyed by id_jabvox. Strips sensitive columns and
# attaches the correlation ids. Never raises to the caller path — the job handles retries.
class Jabvox::ExternalExport::RowExporterService
  def initialize(target)
    @target = target
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
  end

  # record is a jabvox model instance whose class is in the catalog.
  # Single-record path (real-time mirror): one guarded, one-connection upsert.
  def export(record)
    model = record.class
    return unless Jabvox::ExternalExport::Catalog.exportable_models.include?(model)

    guard!
    plan = row_plan(record)
    return if plan.nil?

    @adapter.upsert_row(plan[:table], plan[:values], conflict_key: plan[:key])
  end

  # Batch path (backfill): write with an already-open client so a whole batch
  # reuses ONE connection. Returns true if written, false if skipped.
  def export_on(client, record)
    return false unless Jabvox::ExternalExport::Catalog.exportable_models.include?(record.class)

    plan = row_plan(record)
    return false if plan.nil?

    @adapter.upsert_row_on(client, plan[:table], plan[:values], conflict_key: plan[:key])
    true
  end

  # Public plan accessor for the batch backfill: { table:, values:, key: } or nil.
  def plan_for(record)
    return nil unless Jabvox::ExternalExport::Catalog.exportable_models.include?(record.class)

    row_plan(record)
  end

  private

  # { table:, values:, key: } for the record given the target's mode, or nil when
  # the record's table must be skipped (map mode without a valid mapping/key).
  def row_plan(record)
    table = Jabvox::ExternalExport::Catalog.table_name_for(record.class)
    @target.map_mode? ? mapped_plan(record, table) : create_plan(record, table)
  end

  # create mode: mirror all safe columns + correlation ids, keyed by id_jabvox.
  def create_plan(record, table)
    { table: table, values: safe_values(record).merge(correlation_ids(record)), key: 'id_jabvox' }
  end

  # map mode: ONLY the mapped columns, renamed to the customer's columns, keyed by
  # the customer's key column. Tables without a mapping or a designated key are
  # skipped (never guessed) — nothing is written blindly and re-syncs never duplicate.
  def mapped_plan(record, table)
    mapping = @target.mapping_for(table)
    return nil if mapping.nil?

    key_col = mapping['key']
    return nil if key_col.blank?

    safe = Jabvox::ExternalExport::Catalog.safe_columns(record.class)
    values = {}
    mapping['columns'].each do |jabvox_col, customer_col|
      next unless safe.include?(jabvox_col.to_s) # whitelist: only real, non-sensitive cols

      values[customer_col.to_s] = record[jabvox_col.to_s]
    end
    return nil if values.empty? || !values.key?(key_col)

    { table: table, values: values, key: key_col }
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

  # id_jabvox always; the external-DB ids only when the record is a lead linked to
  # an import source (so reports on the far side can join back).
  def correlation_ids(record)
    ids = { 'id_jabvox' => record.id, 'id_db_externa' => nil, 'id_leads_db_externa' => nil }
    if record.is_a?(JabvoxLead)
      link = record.jabvox_lead_source_records.first
      ids['id_leads_db_externa'] = link&.external_id_jabvox
    end
    ids
  end
end
