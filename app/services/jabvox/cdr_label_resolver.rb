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
    # 2) Match por linkedid: el dialer guarda el linkedid (comun a todos los legs),
    #    y el CDR lo trae en su columna linkedid. Cubre las llamadas cuyo uniqueid
    #    del CDR (leg del trunk) NO coincide con el uniqueid guardado (otro leg).
    add_dialer_by_linkedid(by_uid, rows)
    # 3) Para las que aun no matchean (historico sin linkedid, o no-conectadas):
    #    numero+tiempo y, para el dialer, agente(extension)+tiempo.
    unmatched = rows.reject { |r| enrichment_for_row(r, by_uid) }
    return by_uid if unmatched.empty?

    add_dialer_by_number(by_uid, unmatched)
    add_click_to_call_by_number(by_uid, unmatched)
    add_dialer_by_agent_time(by_uid, unmatched)
    by_uid
  end

  # Returns the enrichment for a single row: exact uniqueid, then linkedid, then
  # the number+time or agent+time fallbacks, and finally — para llamadas ENTRANTES
  # (del trunk del proveedor a una extensión, sin call log interno) — un enrichment
  # derivado del propio CDR (origen = número externo, destino = agente).
  def enrichment_for_row(row, lookup)
    uid = row['uniqueid'].to_s
    return lookup[uid] if lookup.key?(uid)

    lid = row['linkedid'].to_s
    return lookup["lid:#{lid}"] if lid.present? && lookup.key?("lid:#{lid}")

    return lookup["num:#{number_key(row)}"] if lookup.key?("num:#{number_key(row)}")

    agent_time_enrichment(row)
  end

  # Enrichment de último recurso para LLAMADAS ENTRANTES: la llamada entra por el
  # trunk del proveedor (channel = SIP/ipcom-…) hacia una extensión de agente
  # (dstchannel = SIP/105-…). No tiene call log interno (el agente no la originó),
  # así que la resolvemos con el propio CDR: origen = número externo (src),
  # destino = el agente que la recibió. Se usa SOLO cuando ningún match de saliente
  # (uniqueid/linkedid/número/agente+tiempo) aplicó, para no pisar el dialer.
  def enrichment_for_row_with_inbound(row, lookup)
    enrichment_for_row(row, lookup) || inbound_enrichment(row)
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

  # Match por linkedid: cruza el linkedid del CDR contra linkedid_jabvox del call
  # log. Guarda bajo "lid:<linkedid>". Es el match fiable para el dialer, porque el
  # linkedid es el mismo en todos los legs y coincide con el del CDR.
  def add_dialer_by_linkedid(lookup, rows)
    lids = rows.map { |r| r['linkedid'].to_s }.reject(&:blank?).uniq
    return if lids.empty?

    @account.jabvox_dialer_call_logs
            .where(linkedid_jabvox: lids)
            .includes(:typification)
            .find_each do |log|
      lookup["lid:#{log.linkedid_jabvox}"] ||= dialer_enrichment(log)
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

  # Ventana (segundos) para el match por agente+tiempo del histórico del dialer.
  AGENT_TIME_WINDOW = 120

  # Fallback para llamadas del dialer del HISTÓRICO (sin linkedid guardado) cuyo
  # uniqueid tampoco coincide y cuyo número no está en el CDR (dst='s'). Cruza por
  # la extensión del agente (del dstchannel del CDR) + cercanía de tiempo contra el
  # call log del dialer. Clave: "agent:<ext>:<epoch>" por cada log; enrichment_for_row
  # busca la de su row dentro de la ventana.
  def add_dialer_by_agent_time(lookup, rows)
    dialer_rows = rows.select { |r| PLACEHOLDER_DST.include?(r['dst'].to_s) }
    return if dialer_rows.empty?

    span = rows_time_span(dialer_rows)
    return if span.nil?

    # Índice { extensión => [[epoch, enrichment], ...] } de los call logs del
    # dialer en la ventana; enrichment_for_row busca el más cercano en el tiempo.
    @agent_time_index ||= build_agent_time_index(span)
  end

  def build_agent_time_index(span)
    idx = Hash.new { |h, k| h[k] = [] }
    @account.jabvox_dialer_call_logs
            .where(started_at_jabvox: span)
            .where.not(agent_id_jabvox: nil)
            .includes(:typification)
            .find_each do |log|
      ext = agent_extension_for(log.agent_id_jabvox)
      next if ext.blank? || log.started_at_jabvox.blank?

      idx[ext] << [log.started_at_jabvox.to_i, dialer_enrichment(log)]
    end
    idx
  end

  # Enrichment de un row por agente+tiempo: extensión del agente (del CDR) + el
  # call log del dialer de esa extensión cuyo inicio esté dentro de AGENT_TIME_WINDOW.
  def agent_time_enrichment(row)
    return nil unless @agent_time_index

    ext = cdr_agent_extension(row)
    t = parse_calldate(row['calldate'])
    return nil if ext.blank? || t.nil?

    candidates = @agent_time_index[ext]
    return nil if candidates.blank?

    base = t.to_i
    best = candidates.min_by { |epoch, _| (epoch - base).abs }
    return nil if best.nil? || (best.first - base).abs > AGENT_TIME_WINDOW

    best.last
  end

  # ¿Es una llamada ENTRANTE? Entra por el trunk del proveedor (channel NO es una
  # extensión numérica: SIP/ipcom-…) hacia una extensión de agente (dstchannel =
  # SIP/105-…). Distinta del dialer saliente porque el dialer SÍ tiene call log
  # interno (ya matcheado antes); esto es el último recurso cuando nada matcheó.
  def inbound?(row)
    ch  = row['channel'].to_s
    dch = row['dstchannel'].to_s
    # El leg de origen NO es una extensión numérica (es el trunk: SIP/ipcom-…),
    # y el leg de destino SÍ es una extensión numérica de agente (SIP/105-…).
    channel_is_trunk = ch.present? && !numeric_extension?(ch)
    channel_is_trunk && numeric_extension?(dch)
  end

  # true si el channel apunta a una extensión NUMÉRICA (SIP/105-…), no a un trunk.
  def numeric_extension?(channel)
    ext = extension_from_channel(channel)
    ext.present? && ext.match?(/\A\d+\z/)
  end

  # Enrichment de una entrante del proveedor hacia el agente. Es parte del flujo del
  # MARCADOR (el lead marcado devuelve la llamada y la atiende el agente), así que:
  #   - medio  = 'dialer' (no se distingue dirección)
  #   - destino = el NÚMERO DEL LEAD que se marcó — no está en el CDR (dst='s'), se
  #     recupera del call log del dialer de ese agente más cercano en el tiempo.
  #   - agente = la extensión que recibió (dstchannel). origin_for ya deja el DID
  #     (src) como origen, y agent_channel_label ya pone al agente como canal origen.
  def inbound_enrichment(row)
    return nil unless inbound?(row)

    ext = extension_from_channel(row['dstchannel'])
    agent = user_name_for(ext) || ext
    lead = inbound_lead_number(row, ext)
    {
      medium: 'dialer',
      typification_id: nil,
      typification: nil,
      # origin lo resuelve origin_for con el src (DID); destination = número del lead.
      origin: nil,
      destination: lead,
      agent_name: agent
    }
  end

  # Ventana (segundos) para asociar una entrante con el lead que el marcador marcó a
  # ese agente. Más amplia que AGENT_TIME_WINDOW porque el lead puede devolver la
  # llamada bastante después de que el marcador lo intentó.
  INBOUND_LEAD_WINDOW = 3600

  # Número del lead de una entrante: el phone del último call log del dialer de esa
  # extensión de agente ANTES (o alrededor) de la hora de la entrada. Devuelve nil
  # si no hay un candidato razonable (entonces el destino queda como el crudo).
  def inbound_lead_number(row, ext)
    t = parse_calldate(row['calldate'])
    return nil if ext.blank? || t.nil?

    idx = inbound_agent_index
    candidates = idx[ext]
    return nil if candidates.blank?

    base = t.to_i
    best = candidates.min_by { |epoch, _phone| (epoch - base).abs }
    return nil if best.nil? || (best.first - base).abs > INBOUND_LEAD_WINDOW

    best.last
  end

  # Índice { extensión_agente => [[epoch, phone_lead], ...] } de los call logs del
  # dialer, para asociar entrantes con el lead marcado. Se construye una vez.
  def inbound_agent_index
    @inbound_agent_index ||= begin
      idx = Hash.new { |h, k| h[k] = [] }
      @account.jabvox_dialer_call_logs
              .where.not(agent_id_jabvox: nil)
              .where.not(phone_jabvox: [nil, ''])
              .find_each do |log|
        ext = agent_extension_for(log.agent_id_jabvox)
        t = log.started_at_jabvox
        next if ext.blank? || t.blank?

        idx[ext] << [t.to_i, log.phone_jabvox]
      end
      idx
    end
  end

  # Extensión del agente desde el CDR: en el dialer el agente está en dstchannel
  # (SIP/105-...); en click-to-call en channel. Tomamos el leg numérico.
  def cdr_agent_extension(row)
    %w[dstchannel channel].each do |field|
      raw = row[field].to_s
      ext = raw.sub(%r{\A(?:SIP|PJSIP)/}i, '').sub(/-.*\z/, '')
      return ext if ext.match?(/\A\d+\z/)
    end
    nil
  end

  def agent_extension_for(user_id)
    return nil if user_id.blank?

    @agent_ext ||= {}
    @agent_ext[user_id] ||= @account.jabvox_user_extensions.where(user_id: user_id).pick(:extension_jabvox)
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
