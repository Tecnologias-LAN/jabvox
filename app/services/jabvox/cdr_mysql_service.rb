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
      # Enrich by uniqueid first, then by number+time so dialer/click-to-call calls
      # that never connected (busy/no-answer/failed) are still identified.
      enrichment = resolver.enrichment_for_rows(rows)
      { records: rows.map { |row| normalize(row, enrichment) }, total: total }
    end
  rescue Mysql2::Error, StandardError => e
    Rails.logger.error "[CDR] records query failed: #{e.message}"
    { records: [], total: 0, error: e.message }
  end

  # Lote incremental para la sincronización local: filas crudas del PBX con
  # calldate > `since` (o desde el inicio si since es nil), ordenadas ASC por
  # calldate para poder avanzar el cursor de forma segura. Cada fila ya viene con
  # su enrichment aplicado (mismo normalize que el reporte usaba al vuelo), para
  # materializarla en jabvox_cdr_records. `limit` acota cada corrida.
  # Devuelve un array de hashes normalizados (NO { records:, total: }).
  def fetch_batch_since(since, limit: 1000)
    clauses = []
    binds = []
    if since.present?
      clauses << 'calldate > ?'
      binds << since
    end
    where_sql = clauses.any? ? "WHERE #{clauses.join(' AND ')}" : ''

    with_client do |client|
      stmt = client.prepare(
        'SELECT uniqueid, linkedid, calldate, src, dst, channel, dstchannel, ' \
        'disposition, duration, billsec, recordingfile ' \
        "FROM #{table} #{where_sql} ORDER BY calldate ASC LIMIT ?"
      )
      rows = stmt.execute(*binds, limit.to_i.clamp(1, 5000), as: :hash).to_a
      enrichment = resolver.enrichment_for_rows(rows)
      rows.map { |row| normalize(row, enrichment) }
    end
  end

  # Aggregated per-agent summary (answered, no_answer, busy, failed, talk time, answer rate).
  # Groups by the AGENT'S extension, taken from the channel (e.g. "SIP/104-00000004"
  # -> "104"), not by the dialed number. The extension is resolved to the agent's
  # name later (normalize_summary); if it isn't mapped, the bare extension is shown.
  def summary(filters = {})
    where_sql, binds = build_where(filters)

    # Extract the AGENT extension. The agent leg is numeric (e.g. "1501"); the trunk
    # leg is alphabetic (e.g. "ipcom"). For click-to-call the agent is `channel`; for
    # the dialer it's `dstchannel` (channel = trunk). So: take the extension from
    # `channel` when it's numeric, otherwise from `dstchannel`. Strips the tech prefix
    # ("SIP/") and the "-<uniqueid>" suffix on the chosen leg.
    chan_ext = "SUBSTRING_INDEX(SUBSTRING_INDEX(channel, '/', -1), '-', 1)"
    dst_ext  = "SUBSTRING_INDEX(SUBSTRING_INDEX(dstchannel, '/', -1), '-', 1)"
    ext_expr = "CASE WHEN #{chan_ext} REGEXP '^[0-9]+$' THEN #{chan_ext} " \
               "WHEN #{dst_ext} REGEXP '^[0-9]+$' THEN #{dst_ext} ELSE #{chan_ext} END"

    with_client do |client|
      stmt = client.prepare(
        "SELECT #{ext_expr} AS agent_ext, " \
        'COUNT(*) AS total, ' \
        "SUM(disposition = 'ANSWERED') AS answered, " \
        "SUM(disposition = 'NO ANSWER') AS no_answer, " \
        "SUM(disposition = 'BUSY') AS busy, " \
        "SUM(disposition = 'FAILED') AS failed, " \
        'SUM(billsec) AS talk_seconds ' \
        "FROM #{table} #{where_sql} #{where_sql.empty? ? 'WHERE' : 'AND'} channel != '' " \
        "GROUP BY #{ext_expr} ORDER BY total DESC"
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
      'SELECT uniqueid, linkedid, calldate, src, dst, channel, dstchannel, ' \
      'disposition, duration, billsec, recordingfile ' \
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
      # Match the extension as caller, callee, or the agent's channel — en CUALQUIER
      # leg (channel O dstchannel). Click-to-call tiene al agente en channel; el
      # DIALER lo tiene en dstchannel (channel es el trunk SIP/ipcom-...). Sin mirar
      # dstchannel, filtrar por la extensión del agente NO encontraba las del dialer.
      clauses << '(src = ? OR dst = ? OR channel LIKE ? OR channel LIKE ? OR dstchannel LIKE ? OR dstchannel LIKE ?)'
      ext = filters[:extension]
      binds << ext << ext << "SIP/#{ext}-%" << "PJSIP/#{ext}-%" << "SIP/#{ext}-%" << "PJSIP/#{ext}-%"
    end
    # Extension RANGE filter (e.g. 100..200): la extensión del agente tomada del leg
    # que sea numérico (channel para click-to-call, dstchannel para el dialer),
    # comparada numéricamente. Solo extensiones de solo-dígitos entran al rango.
    if filters[:ext_from].present? || filters[:ext_to].present?
      chan_raw = "SUBSTRING_INDEX(SUBSTRING_INDEX(channel, '/', -1), '-', 1)"
      dst_raw  = "SUBSTRING_INDEX(SUBSTRING_INDEX(dstchannel, '/', -1), '-', 1)"
      # La extensión del agente: el leg numérico (channel si es numérico, si no dstchannel).
      raw_ext = "(CASE WHEN #{chan_raw} REGEXP '^[0-9]+$' THEN #{chan_raw} ELSE #{dst_raw} END)"
      ext_num = "CAST(#{raw_ext} AS UNSIGNED)"
      clauses << "#{raw_ext} REGEXP '^[0-9]+$'"
      if filters[:ext_from].present?
        clauses << "#{ext_num} >= ?"
        binds << filters[:ext_from].to_s.gsub(/\D/, '').to_i
      end
      if filters[:ext_to].present?
        clauses << "#{ext_num} <= ?"
        binds << filters[:ext_to].to_s.gsub(/\D/, '').to_i
      end
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
    info = resolver.enrichment_for_row(row, enrichment)
    {
      uniqueid: row['uniqueid'],
      linkedid: row['linkedid'],
      calldate: row['calldate'],
      src: row['src'],
      dst: row['dst'],
      # Crudos conservados para la tabla local (trazabilidad + filtro por extensión).
      channel_raw: row['channel'],
      dstchannel_raw: row['dstchannel'],
      # Origin / destination, with the dialer's 0000/s placeholders replaced by real data,
      # and agent extensions resolved to names.
      origin: resolver.origin_for(row, info),
      destination: resolver.destination_for(row, info),
      # Origin channel = the AGENT. For click-to-call the agent is the origin leg,
      # but for the dialer the agent is the DESTINATION leg (origin is the trunk).
      # agent_channel_label picks the right leg (or the enriched agent name) so a
      # dialer call shows the agent, not "ipcom".
      origin_channel: resolver.agent_channel_label(row, info),
      # The agent's raw extension, taken from whichever leg carries it.
      agent_extension: resolver.agent_extension_from_row(row),
      dst_channel: row['dstchannel'].presence,
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
    # The agent's extension, extracted from the channel by the GROUP BY query.
    # Resolves to the agent's name, or shows the bare extension when unmapped.
    extension = row['agent_ext']
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
