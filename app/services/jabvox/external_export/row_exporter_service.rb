# Exports a single record (any exportable jabvox model) to the account's external
# DB as a parameterized upsert keyed by id_jabvox. Strips sensitive columns and
# attaches the correlation ids. Never raises to the caller path — the job handles retries.
class Jabvox::ExternalExport::RowExporterService
  def initialize(target)
    @target = target
    @adapter = Jabvox::ExternalExport::WriteAdapter.new(target)
  end

  # record is a jabvox model instance whose class is in the catalog.
  def export(record)
    model = record.class
    return unless Jabvox::ExternalExport::Catalog.exportable_models.include?(model)

    guard!
    values = safe_values(record).merge(correlation_ids(record))
    @adapter.upsert_row(Jabvox::ExternalExport::Catalog.table_name_for(model), values)
  end

  private

  def guard!
    result = Jabvox::Analytics::HostGuardService.new(
      host: @target.host_jabvox, port: @target.effective_port,
      allow_private: @target.allow_private_network_jabvox
    ).call
    raise Jabvox::ExternalExport::WriteAdapter::ConnectionError, result.reason unless result.allowed?
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
