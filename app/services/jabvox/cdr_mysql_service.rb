require 'mysql2'

# Reads Call Detail Records from an external Asterisk/Issabel MySQL database.
# Connections are short-lived and scoped to a single account's CdrConfig.
class Jabvox::CdrMysqlService
  CONNECT_TIMEOUT = 8
  DISPOSITIONS = ['ANSWERED', 'NO ANSWER', 'BUSY', 'FAILED'].freeze

  def initialize(config, account: nil)
    @config = config
    @account = account
  end

  # Verifies the credentials by opening a connection and running a trivial query.
  def test_connection
    with_client do |client|
      client.query("SELECT 1 FROM #{table} LIMIT 1")
      { success: true, message: 'Conexión con la base de datos del PBX establecida.' }
    end
  rescue Mysql2::Error, StandardError => e
    { success: false, message: e.message }
  end

  # Paginated records with optional filters. Returns { records:, total: }.
  def records(filters = {}, page: 1, per_page: 50)
    page = [page.to_i, 1].max
    per_page = per_page.to_i.clamp(1, 200)
    offset = (page - 1) * per_page

    where_sql, binds = build_where(filters)

    with_client do |client|
      total = count_rows(client, where_sql, binds)
      rows = fetch_rows(client, where_sql, binds, per_page, offset)
      enrichment = resolver.enrichment_lookup(rows.map { |r| r['uniqueid'] })
      { records: rows.map { |row| normalize(row, enrichment) }, total: total }
    end
  rescue Mysql2::Error, StandardError => e
    Rails.logger.error "[CDR] records query failed: #{e.message}"
    { records: [], total: 0, error: e.message }
  end

  # Aggregated per-agent summary (answered, no_answer, busy, failed, talk time, answer rate).
  def summary(filters = {})
    where_sql, binds = build_where(filters)

    with_client do |client|
      stmt = client.prepare(
        'SELECT src AS agent, ' \
        'COUNT(*) AS total, ' \
        "SUM(disposition = 'ANSWERED') AS answered, " \
        "SUM(disposition = 'NO ANSWER') AS no_answer, " \
        "SUM(disposition = 'BUSY') AS busy, " \
        "SUM(disposition = 'FAILED') AS failed, " \
        'SUM(billsec) AS talk_seconds ' \
        "FROM #{table} #{where_sql} #{where_sql.empty? ? 'WHERE' : 'AND'} src != '' GROUP BY src ORDER BY total DESC"
      )
      stmt.execute(*binds, as: :hash).map { |row| normalize_summary(row) }
    end
  rescue Mysql2::Error, StandardError => e
    Rails.logger.error "[CDR] summary query failed: #{e.message}"
    []
  end

  # Looks up the recording filename for a single call (used before SFTP download).
  def recording_file(uniqueid)
    with_client do |client|
      stmt = client.prepare("SELECT recordingfile FROM #{table} WHERE uniqueid = ? LIMIT 1")
      row = stmt.execute(uniqueid.to_s, as: :hash).first
      row && row['recordingfile'].presence
    end
  rescue Mysql2::Error, StandardError => e
    Rails.logger.error "[CDR] recording lookup failed: #{e.message}"
    nil
  end

  private

  def table
    # Identifier, not a bind value — validated to a safe charset in the model + here.
    @config.mysql_table.to_s.gsub(/[^a-zA-Z0-9_]/, '')
  end

  def with_client
    client = Mysql2::Client.new(
      host: @config.mysql_host,
      port: @config.mysql_port,
      username: @config.mysql_username,
      password: @config.mysql_password,
      database: @config.mysql_database,
      connect_timeout: CONNECT_TIMEOUT,
      read_timeout: CONNECT_TIMEOUT,
      reconnect: false
    )
    yield client
  ensure
    client&.close
  end

  def count_rows(client, where_sql, binds)
    stmt = client.prepare("SELECT COUNT(*) AS c FROM #{table} #{where_sql}")
    stmt.execute(*binds, as: :hash).first['c'].to_i
  end

  def fetch_rows(client, where_sql, binds, per_page, offset)
    stmt = client.prepare(
      'SELECT uniqueid, calldate, src, dst, disposition, duration, billsec, recordingfile ' \
      "FROM #{table} #{where_sql} ORDER BY calldate DESC LIMIT ? OFFSET ?"
    )
    stmt.execute(*binds, per_page, offset, as: :hash)
  end

  # Builds a parametrized WHERE clause; every value is passed as a bind to avoid injection.
  def build_where(filters)
    clauses = []
    binds = []

    if filters[:from].present?
      clauses << 'calldate >= ?'
      binds << filters[:from]
    end
    if filters[:to].present?
      clauses << 'calldate <= ?'
      binds << filters[:to]
    end
    if filters[:extension].present?
      clauses << '(src = ? OR dst = ?)'
      binds << filters[:extension] << filters[:extension]
    end
    if filters[:src].present?
      clauses << 'src = ?'
      binds << filters[:src]
    end
    if filters[:dst].present?
      clauses << 'dst = ?'
      binds << filters[:dst]
    end
    if filters[:disposition].present? && DISPOSITIONS.include?(filters[:disposition])
      clauses << 'disposition = ?'
      binds << filters[:disposition]
    end

    where_sql = clauses.any? ? "WHERE #{clauses.join(' AND ')}" : ''
    [where_sql, binds]
  end

  def normalize(row, enrichment = {})
    info = enrichment[row['uniqueid'].to_s]
    {
      uniqueid: row['uniqueid'],
      calldate: row['calldate'],
      src: row['src'],
      dst: row['dst'],
      # Origin / destination, with the dialer's 0000/s placeholders replaced by real data,
      # and agent extensions resolved to names.
      origin: resolver.origin_for(row, info),
      destination: resolver.destination_for(row, info),
      # Medium: how the call was placed (click_to_call | dialer | manual when unknown).
      medium: info&.dig(:medium) || 'manual',
      agent_name: info&.dig(:agent_name),
      disposition: row['disposition'],
      duration: row['duration'].to_i,
      billsec: row['billsec'].to_i,
      recording_file: row['recordingfile'].presence,
      typification: info&.dig(:typification),
      typification_id: info&.dig(:typification_id)
    }
  end

  def normalize_summary(row)
    total = row['total'].to_i
    answered = row['answered'].to_i
    extension = row['agent'] # the src extension, grouped by the query
    {
      agent: resolver.user_name_for(extension) || extension,
      agent_extension: extension,
      user_id: resolver.user_id_for(extension),
      total: total,
      answered: answered,
      no_answer: row['no_answer'].to_i,
      busy: row['busy'].to_i,
      failed: row['failed'].to_i,
      talk_seconds: row['talk_seconds'].to_i,
      answer_rate: total.zero? ? 0 : ((answered.to_f / total) * 100).round(1)
    }
  end

  # Resolves agent names, origin/destination and typifications for this account.
  def resolver
    @resolver ||= Jabvox::CdrLabelResolver.new(@account)
  end
end
