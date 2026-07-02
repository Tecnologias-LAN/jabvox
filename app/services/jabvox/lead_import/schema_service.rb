# Lists the tables (and their columns) of the external database, so the UI can let
# the user pick a table and map its columns. Read-only + SSRF-guarded via the adapter.
class Jabvox::LeadImport::SchemaService
  def initialize(lead_source)
    @source = lead_source
  end

  # [{ name:, type:, columns: [{ name:, type:, nullable:, ... }] }]
  def tables
    guard = host_guard
    raise Jabvox::LeadImport::SyncService::Error, guard.reason if guard && !guard.allowed?

    Jabvox::Analytics::AdapterFactory.for(@source).schema_introspection
  end

  # Columns of a single table (from the full introspection).
  def columns(table_name)
    tables.find { |t| t[:name].to_s == table_name.to_s }&.dig(:columns) || []
  end

  private

  def host_guard
    Jabvox::Analytics::HostGuardService.new(
      host: @source.host_jabvox, port: @source.effective_port,
      allow_private: @source.allow_private_network_jabvox
    ).call
  end
end
