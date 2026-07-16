# Resolves human-readable labels for raw CDR data:
#  - extension -> agent/user name (VoIP user extensions are the source of truth, with the
#    CDR-specific extension mappings as a fallback);
#  - PBX call uniqueid -> a full enrichment (medium, real origin/destination, agent name and
#    typification) by joining the internal click-to-call AND dialer call logs.
# All scoped to a single account.
class Jabvox::CdrLabelResolver
  # Asterisk placeholders the dialer leaves in src/dst — meaningless, must be replaced.
  PLACEHOLDER_SRC = %w[0000 s].freeze
  PLACEHOLDER_DST = %w[s 0000].freeze

  def initialize(account)
    @account = account
  end

  # Name for a raw extension, or nil if unknown.
  def user_name_for(extension)
    extension_lookup.dig(extension.to_s, :name)
  end

  # The "origin channel" of a CDR row is the agent's technology channel, e.g.
  # "SIP/104-00000004" or "PJSIP/104-abc". We extract the extension (104) and
  # resolve it to the agent's name; if there's no mapping we return the bare
  # extension, and if the channel isn't parseable we return the raw channel.
  def channel_agent_for(channel)
    raw = channel.to_s
    return nil if raw.blank?

    ext = extension_from_channel(raw)
    return raw if ext.blank?

    user_name_for(ext) || ext
  end

  # Extracts the extension from a channel string: "SIP/104-00000004" -> "104",
  # "PJSIP/1010-abc" -> "1010", "Local/..." -> nil. Returns nil when there's no
  # tech/extension shape.
  def extension_from_channel(channel)
    m = channel.to_s.match(%r{\A(?:SIP|PJSIP|IAX2|DAHDI)/([A-Za-z0-9_]+)-}i)
    m && m[1]
  end

  # The agent extension of a CDR row can live in EITHER leg: for click-to-call the
  # agent is the origin channel (SIP/1501-…), but for the dialer the agent is the
  # DESTINATION channel (channel = trunk SIP/ipcom-…, dstchannel = SIP/1501-…).
  # Returns the extension that maps to a known agent, preferring a mapped one; if
  # neither maps, returns whichever parses (origin first) so we still show something.
  def agent_extension_from_row(row)
    ch_ext  = extension_from_channel(row['channel'])
    dst_ext = extension_from_channel(row['dstchannel'])
    return ch_ext  if ch_ext.present?  && user_name_for(ch_ext).present?
    return dst_ext if dst_ext.present? && user_name_for(dst_ext).present?

    ch_ext.presence || dst_ext.presence
  end

  # Label for the "origin channel" column, which really means "the agent". Prefers
  # the enriched agent name (from the click-to-call / dialer log — the source of
  # truth), then the agent resolved from whichever channel leg carries the agent
  # extension, then the raw origin channel as a last resort.
  def agent_channel_label(row, enrichment)
    name = enrichment&.dig(:agent_name)
    return name if name.present?

    ext = agent_extension_from_row(row)
    return user_name_for(ext) || ext if ext.present?

    row['channel'].to_s.presence
  end

  # user_id for a raw extension, or nil.
  def user_id_for(extension)
    extension_lookup.dig(extension.to_s, :user_id)
  end

  # Maps the given PBX uniqueids => enrichment hash:
  #   { medium:, typification_id:, typification:, origin:, destination:, agent_name: }
  # joining the click-to-call and dialer call logs. One query per source.
  def enrichment_lookup(uniqueids)
    ids = uniqueids.compact.map(&:to_s).uniq
    return {} if @account.nil? || ids.empty?

    lookup = {}
    add_click_to_call(lookup, ids)
    add_dialer(lookup, ids)
    lookup
  end

  # Builds an enrichment for a set of CDR ROWS, not just uniqueids. Matches by
  # uniqueid first (exact), then falls back to number + approximate time so dialer
  # / click-to-call calls that DID NOT connect (busy, no-answer, failed) — and thus
  # never recorded a uniqueid — are still identified as "Marcador"/"Click-to-Call"
  # with their real outcome, instead of showing up as "Manual".
  # Returns a lookup keyed by uniqueid; rows without a uniqueid match get a synthetic
  # key "row:<index>" that normalize() can request via enrichment_for_row.
  def enrichment_for_rows(rows)
    return {} if @account.nil? || rows.blank?

    by_uid = enrichment_lookup(rows.map { |r| r['uniqueid'] })
    # For rows still unmatched, try number + time against BOTH sources.
    unmatched = rows.reject { |r| by_uid.key?(r['uniqueid'].to_s) }
    return by_uid if unmatched.empty?

    add_dialer_by_number(by_uid, unmatched)
    add_click_to_call_by_number(by_uid, unmatched)
    by_uid
  end

  # Returns the enrichment for a single row: exact uniqueid match, else the
  # number+time fallback stored under a "num:<digits>" key.
  def enrichment_for_row(row, lookup)
    uid = row['uniqueid'].to_s
    return lookup[uid] if lookup.key?(uid)

    lookup["num:#{number_key(row)}"]
  end

  # Resolves the displayed origin/destination for a CDR row, replacing Asterisk placeholders
  # with the enriched values when available.
  def origin_for(row, enrichment)
    src = row['src'].to_s
    return enrichment[:origin] if PLACEHOLDER_SRC.include?(src) && enrichment&.dig(:origin).present?

    user_name_for(src) || src.presence
  end

  def destination_for(row, enrichment)
    dst = row['dst'].to_s
    return enrichment[:destination] if PLACEHOLDER_DST.include?(dst) && enrichment&.dig(:destination).present?

    user_name_for(dst) || dst.presence
  end

  private

  def add_click_to_call(lookup, ids)
    @account.jabvox_call_logs
            .where(uniqueid: ids)
            .includes(:typification, :user)
            .find_each do |log|
      lookup[log.uniqueid.to_s] = {
        medium: 'click_to_call',
        typification_id: log.typification_id,
        typification: log.typification&.name,
        origin: log.user&.name || log.extension.presence,
        destination: log.phone_number.presence,
        agent_name: log.user&.name
      }
    end
  end

  def add_dialer(lookup, ids)
    @account.jabvox_dialer_call_logs
            .where(uniqueid_jabvox: ids)
            .includes(:typification)
            .find_each do |log|
      lookup[log.uniqueid_jabvox.to_s] ||= dialer_enrichment(log)
    end
  end

  # How many trailing digits to compare when matching by number (ignores the
  # provider prefix and country code differences between CDR and our stored number).
  MATCH_TAIL = 8
  # Time window (seconds) around the CDR calldate to accept a number match.
  NUMBER_MATCH_WINDOW = 180

  # Fallback match: dialer logs by dialed number + time, for rows with no uniqueid
  # match (typically busy / no-answer / failed calls that never bridged).
  def add_dialer_by_number(lookup, rows)
    span = rows_time_span(rows)
    return if span.nil?

    logs = @account.jabvox_dialer_call_logs
                   .where(started_at_jabvox: span)
                   .includes(:typification)
                   .to_a
    index_by_number(logs, ->(l) { l.phone_jabvox }, ->(l) { l.started_at_jabvox })
      .each do |num, log|
      key = "num:#{num}"
      lookup[key] ||= dialer_enrichment(log)
    end
  end

  def add_click_to_call_by_number(lookup, rows)
    span = rows_time_span(rows)
    return if span.nil?

    logs = @account.jabvox_call_logs
                   .where(called_at: span)
                   .includes(:typification, :user)
                   .to_a
    index_by_number(logs, ->(l) { l.phone_number }, ->(l) { l.called_at })
      .each do |num, log|
      key = "num:#{num}"
      # Don't override a dialer match already found for the same number key.
      lookup[key] ||= {
        medium: 'click_to_call',
        typification_id: log.typification_id,
        typification: log.typification&.name,
        origin: log.user&.name || log.extension.presence,
        destination: log.phone_number.presence,
        agent_name: log.user&.name
      }
    end
  end

  def dialer_enrichment(log)
    {
      medium: 'dialer',
      typification_id: log.typification_id,
      typification: log.typification&.name,
      origin: dialer_agent_name(log),
      destination: log.phone_jabvox.presence,
      agent_name: dialer_agent_name(log)
    }
  end

  # Builds { number_tail => newest log } from a list of logs, keyed by the last
  # MATCH_TAIL digits of their phone number.
  def index_by_number(logs, phone_fn, _time_fn)
    idx = {}
    logs.each do |log|
      tail = digits_tail(phone_fn.call(log))
      next if tail.blank?

      idx[tail] ||= log # logs come newest-first is not guaranteed; keep first seen
    end
    idx
  end

  # The last MATCH_TAIL digits of the CDR row's dialed number (dst, falling back to
  # src), used as the number-match key.
  def number_key(row)
    digits_tail(row['dst']) || digits_tail(row['src'])
  end

  def digits_tail(value)
    digits = value.to_s.gsub(/\D/, '')
    return nil if digits.length < MATCH_TAIL

    digits[-MATCH_TAIL..]
  end

  # A time range covering all rows ± the match window, to bound the fallback query.
  def rows_time_span(rows)
    times = rows.map { |r| parse_calldate(r['calldate']) }.compact
    return nil if times.empty?

    (times.min - NUMBER_MATCH_WINDOW)..(times.max + NUMBER_MATCH_WINDOW)
  end

  def parse_calldate(value)
    return value if value.is_a?(Time)

    Time.zone.parse(value.to_s)
  rescue StandardError
    nil
  end

  def dialer_agent_name(log)
    return nil if log.agent_id_jabvox.blank?

    @agent_names ||= {}
    @agent_names[log.agent_id_jabvox] ||= User.where(id: log.agent_id_jabvox).pick(:name)
  end

  # "extension" => { name:, user_id: }. Built once.
  def extension_lookup
    @extension_lookup ||= build_extension_lookup
  end

  def build_extension_lookup
    return {} if @account.nil?

    lookup = {}
    # CDR-specific labels/users first (lower priority), so VoIP can override below.
    @account.jabvox_cdr_extension_mappings.includes(:user).find_each do |mapping|
      name = mapping.user&.name || mapping.label.presence
      lookup[mapping.extension.to_s] = { name: name, user_id: mapping.user_id } if name
    end
    # VoIP user extensions are the authoritative source of truth.
    @account.jabvox_user_extensions.includes(:user).find_each do |ext|
      lookup[ext.extension_jabvox.to_s] = { name: ext.user&.name, user_id: ext.user_id }
    end
    lookup
  end
end
