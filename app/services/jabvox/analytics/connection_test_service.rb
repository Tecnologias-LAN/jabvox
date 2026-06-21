# Tests connectivity to a data source: runs the SSRF host guard, then opens a real
# connection through the adapter and measures latency. Returns a sanitized result and
# (for saved sources) updates status_jabvox / last_tested_at_jabvox.
class Jabvox::Analytics::ConnectionTestService
  def initialize(data_source)
    @data_source = data_source
  end

  def call
    guard = host_guard_result
    return failure(guard.reason) if guard && !guard.allowed?

    adapter = Jabvox::Analytics::AdapterFactory.for(@data_source)
    result = adapter.test_connection
    persist_status(result)
    result
  rescue ArgumentError => e
    failure(e.message)
  end

  private

  # SQLite has no network host, so the SSRF guard is skipped (path is validated elsewhere).
  def host_guard_result
    return nil if @data_source.sqlite?

    Jabvox::Analytics::HostGuardService.new(
      host: @data_source.host_jabvox,
      port: @data_source.effective_port,
      allow_private: @data_source.allow_private_network_jabvox
    ).call
  end

  def persist_status(result)
    return unless @data_source.persisted?

    @data_source.update!(
      status_jabvox: result[:success] ? 'ok' : 'error',
      last_tested_at_jabvox: Time.current
    )
  end

  def failure(message)
    { success: false, latency_ms: nil, message: message }
  end
end
