# Writes append-only audit rows for the Analytics module. Metadata is sanitized here so
# secrets (passwords, connection strings, full SQL with literals) never reach the log.
#
#   Jabvox::Analytics::AuditService.new(account: acc, user: u, request: request)
#     .record(action: 'connection.test', result: 'success', auditable: data_source, metadata: { latency_ms: 42 })
class Jabvox::Analytics::AuditService
  # Keys that must never be persisted, even if a caller passes them by mistake.
  SECRET_KEYS = %w[password password_jabvox secret token api_key api_secret ssh_password
                   ssl_ca ssl_ca_jabvox connection_string dsn].freeze
  SQL_SNIPPET_LIMIT = 500

  def initialize(account:, user: nil, request: nil)
    @account = account
    @user = user
    @request = request
  end

  def record(action:, result: 'success', auditable: nil, metadata: {})
    JabvoxAnalyticsAuditLog.create!(
      account: @account, user: @user,
      action_jabvox: action.to_s, result_jabvox: result.to_s,
      auditable_type_jabvox: auditable&.class&.name, auditable_id_jabvox: auditable&.id,
      metadata_jabvox: sanitize(metadata),
      **request_attributes
    )
  rescue StandardError => e
    # Auditing must never break the request it observes.
    Rails.logger.error "[Analytics::Audit] failed to record #{action}: #{e.message}"
    nil
  end

  private

  def request_attributes
    return { ip_address_jabvox: nil, user_agent_jabvox: nil } if @request.nil?

    { ip_address_jabvox: @request.remote_ip, user_agent_jabvox: @request.user_agent.to_s.slice(0, 255) }
  end

  def sanitize(metadata)
    return {} if metadata.blank?

    metadata.to_h.each_with_object({}) do |(key, value), acc|
      key_s = key.to_s
      next if SECRET_KEYS.include?(key_s)

      acc[key_s] = key_s == 'sql' ? truncate_sql(value) : sanitize_value(value)
    end
  end

  def sanitize_value(value)
    case value
    when Hash then sanitize(value)
    when Array then value.map { |v| sanitize_value(v) }
    when String then value.slice(0, 1000)
    else value
    end
  end

  def truncate_sql(sql)
    sql.to_s.gsub(/\s+/, ' ').strip.slice(0, SQL_SNIPPET_LIMIT)
  end
end
