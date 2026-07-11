# Reads every row from the external table and creates/updates leads in the account.
#
# Identity & rules (per product spec):
# - Each external row is identified by external_id_column. The link external_id ↔ lead
#   is stored in JabvoxLeadSourceRecord so re-syncs update the same lead.
# - Contacts are matched by PHONE first; if none matches, a new contact is created with
#   whatever data the row brings (rows are never skipped for missing fields).
# - The external DB is the source of truth: mapped fields are overwritten on each sync.
# - Notes are only ADDED, never updated/removed.
# - All external access is read-only and SSRF-guarded (via the reused adapter).
class Jabvox::LeadImport::SyncService
  Result = Struct.new(:created, :updated, :failed, :errors, keyword_init: true)

  def initialize(lead_source)
    @source = lead_source
    @account = lead_source.account
    @mapping = lead_source.field_mapping_jabvox || {}
  end

  # Read the external table in fixed-size pages so a huge table never loads all
  # rows into memory at once (OOM guard) and nothing is silently truncated.
  PAGE_SIZE = 1000
  MAX_PAGES = 10_000 # hard backstop: up to 10M rows

  def call
    guard = host_guard
    raise Error, guard.reason if guard && !guard.allowed?

    counters = { created: 0, updated: 0, failed: 0 }
    errors = []

    each_page do |rows|
      rows.each do |row|
        outcome = process_row(row)
        counters[outcome] += 1 if counters.key?(outcome)
      rescue StandardError => e
        counters[:failed] += 1
        # Log the detail server-side; keep only a generic, non-leaking message
        # (driver errors can contain host/credentials) tied to the external id.
        Rails.logger.error("[LeadImport::Sync] source=#{@source.id} row=#{row[external_id_column]} #{e.class}: #{e.message}")
        errors << "fila #{row[external_id_column]}: no se pudo importar" if errors.size < 50
      end
    end

    @source.update!(
      last_synced_at_jabvox: Time.current,
      last_sync_result_jabvox: counters.merge(errors: errors, at: Time.current.iso8601)
    )
    Result.new(created: counters[:created], updated: counters[:updated],
               failed: counters[:failed], errors: errors)
  end

  Error = Class.new(StandardError)

  private

  def host_guard
    Jabvox::Analytics::HostGuardService.new(
      host: @source.host_jabvox, port: @source.effective_port,
      allow_private: @source.allow_private_network_jabvox
    ).call
  end

  def external_id_column
    @source.external_id_column_jabvox
  end

  # Yields successive pages of rows (arrays of column=>value hashes). The main
  # table LEFT JOINs each configured related table; related columns are exposed as
  # "alias.column". Every identifier is quoted (no external value is interpolated;
  # only integer LIMIT/OFFSET are).
  def each_page
    adapter = Jabvox::Analytics::AdapterFactory.for(@source)
    select_sql = build_select_sql(adapter)
    # A stable ORDER BY is REQUIRED: without it LIMIT/OFFSET may repeat or skip
    # rows across pages (SQL gives no order guarantee), silently losing leads.
    # We order by the external id — always present and unique per row.
    order_sql = "ORDER BY #{adapter.quote_identifier(@source.table_jabvox)}.#{adapter.quote_identifier(external_id_column)}"
    offset = 0
    MAX_PAGES.times do
      result = adapter.execute("#{select_sql} #{order_sql} LIMIT #{PAGE_SIZE} OFFSET #{offset}",
                               row_limit: PAGE_SIZE)
      rows = result.rows.map { |r| result.columns.zip(r).to_h }
      break if rows.empty?

      yield rows
      break if rows.size < PAGE_SIZE

      offset += PAGE_SIZE
    end
  end

  # Builds "SELECT <cols> FROM main LEFT JOIN related ON ..." with everything
  # quoted. Related table columns are aliased "relalias.col" so names never clash.
  def build_select_sql(adapter)
    q = ->(name) { adapter.quote_identifier(name) }
    main = @source.table_jabvox
    joins = related_tables

    return with_where("SELECT * FROM #{q.call(main)}", adapter) if joins.empty?

    select_parts = ["#{q.call(main)}.*"]
    join_parts = []
    joins.each do |rel|
      tbl = rel['table']
      als = safe_alias(rel['alias'].presence || tbl)
      local = rel['local_key']
      foreign = rel['foreign_key']
      next if tbl.blank? || local.blank? || foreign.blank?

      # Expose related columns as "als.col" via per-column aliases. The alias
      # itself contains a dot ("cstm.saldo_c"), so it must be quoted as ONE
      # identifier — quote_identifier would split it on the dot and emit
      # `cstm`.`col` (invalid as an alias). quote_alias keeps it atomic.
      column_names(adapter, tbl).each do |col|
        select_parts << "#{q.call(als)}.#{q.call(col)} AS #{quote_alias(adapter, "#{als}.#{col}")}"
      end
      # local_key may reference the main table (e.g. "id") or a previously
      # joined alias (e.g. "cstm.mg_c") — this enables chained joins.
      left_ref, left_col = split_local_key(local, main)
      join_parts << "LEFT JOIN #{q.call(tbl)} AS #{q.call(als)} " \
                    "ON #{q.call(als)}.#{q.call(foreign)} = #{q.call(left_ref)}.#{q.call(left_col)}"
    end

    with_where("SELECT #{select_parts.join(', ')} FROM #{q.call(main)} #{join_parts.join(' ')}", adapter)
  end

  def with_where(sql, adapter)
    where = build_where_sql(adapter)
    where.present? ? "#{sql} WHERE #{where}" : sql
  end

  # Filter operators exposed in the mapping UI. Only these reach the SQL.
  FILTER_OPS = {
    'eq' => '=', 'neq' => '<>', 'gt' => '>', 'gte' => '>=', 'lt' => '<', 'lte' => '<='
  }.freeze

  # Builds the WHERE clause from the source's configured row filters.
  # Identifiers are quoted; values are single-quote-escaped literals and any
  # value carrying a backslash or NUL is rejected outright, so no external
  # input can break out of the literal on either MySQL or PostgreSQL.
  def build_where_sql(adapter)
    filters = Array(@source.filters_jabvox).select { |f| f.is_a?(Hash) }
    clauses = filters.filter_map do |f|
      column = f['column'].to_s
      op = f['op'].to_s
      next if column.blank?

      ref, col = split_local_key(column, @source.table_jabvox)
      lhs = "#{adapter.quote_identifier(ref)}.#{adapter.quote_identifier(col)}"
      build_filter_clause(lhs, op, f['value'], f['value2'])
    end
    clauses.join(' AND ')
  end

  def build_filter_clause(lhs, operator, value, value2)
    case operator
    when *FILTER_OPS.keys
      "#{lhs} #{FILTER_OPS[operator]} #{quote_value(value)}"
    when 'between'
      "#{lhs} BETWEEN #{quote_value(value)} AND #{quote_value(value2)}"
    when 'contains'
      "#{lhs} LIKE #{quote_value("%#{value}%")}"
    when 'null' then "#{lhs} IS NULL"
    when 'not_null' then "#{lhs} IS NOT NULL"
    end
  end

  # Safe SQL literal: numbers pass as-is; strings get '' doubling. Backslashes
  # and NUL bytes are rejected (raise) — they are never legitimate filter input
  # and MySQL treats backslash as an escape character inside literals.
  def quote_value(value)
    str = value.to_s
    raise Error, 'valor de filtro inválido' if str.include?('\\') || str.include?("\0")
    return str if str.match?(/\A-?\d+(\.\d+)?\z/)

    "'#{str.gsub("'", "''")}'"
  end

  # Validated related-table configs (only well-formed entries).
  def related_tables
    Array(@source.related_tables_jabvox).select do |r|
      r.is_a?(Hash) && r['table'].present? && r['local_key'].present? && r['foreign_key'].present?
    end
  end

  # Column names of an external table (for building the aliased SELECT list).
  def column_names(adapter, table_name)
    (@schema ||= adapter.schema_introspection)
      .find { |t| t[:name].to_s == table_name.to_s }
      &.dig(:columns)&.map { |c| c[:name] } || []
  end

  # An alias must be a bare identifier; strip anything unsafe.
  def safe_alias(name)
    name.to_s.gsub(/[^a-zA-Z0-9_]/, '')
  end

  # Quotes a column alias as ONE atomic identifier. Unlike quote_identifier
  # (which splits on '.' to build table.column references), an alias like
  # "cstm.saldo_c" is a single name and the dot is part of it. We derive the
  # DB's quote char from quote_identifier of a dot-free token, then wrap the
  # sanitized alias (safe chars + dot) in it.
  def quote_alias(adapter, name)
    quoted = adapter.quote_identifier('x') # => `x` (mysql) or "x" (postgres)
    q = quoted[0]
    cleaned = name.to_s.gsub(/[^a-zA-Z0-9_.]/, '')
    "#{q}#{cleaned}#{q}"
  end

  # Splits a local_key into [table_ref, column]. "cstm.mg_c" joins against the
  # alias "cstm"; a bare "id" joins against the main table. The alias is
  # sanitized so only safe identifiers reach the SQL.
  def split_local_key(local, main)
    if local.to_s.include?('.')
      als, col = local.to_s.split('.', 2)
      [safe_alias(als), col]
    else
      [main, local]
    end
  end

  # Returns :created or :updated.
  def process_row(row)
    external_id = row[external_id_column].to_s
    raise 'sin id externo' if external_id.blank?

    record = @source.records.find_by(external_id_jabvox: external_id)
    lead = record&.jabvox_lead
    creating = lead.nil?

    lead ||= build_lead_for(row)
    apply_mapping(lead, row)

    unless record
      @source.records.create!(account: @account, external_id_jabvox: external_id,
                              jabvox_lead: lead, last_synced_at_jabvox: Time.current)
    end
    record&.update!(last_synced_at_jabvox: Time.current)

    creating ? :created : :updated
  end

  # Finds a contact by phone, then by email (mapped), or creates one with
  # whatever the row brings. Matching on both keys avoids duplicate contacts
  # when a source row shares an email but not a phone with an existing one.
  def build_lead_for(row)
    phone = normalized_phone(mapped_value(row, 'phone'))
    email = normalized_email(mapped_value(row, 'email'))
    contact = find_contact_by_phone(phone) || find_contact_by_email(email)
    contact ||= create_contact(row, phone)
    @account.jabvox_leads.find_or_create_by!(contact: contact)
  end

  # Ensures the lead's campaign is the one named after this connection (the
  # source name). Created once per account and reused; only sets it when the
  # lead has no campaign yet, so a manually-chosen campaign is never overwritten.
  def assign_import_campaign(lead)
    return if @source.name_jabvox.blank?
    return if lead.jabvox_campaign_id.present?

    @import_campaign ||= JabvoxCampaign.find_or_create_by!(
      account: @account, name_jabvox: @source.name_jabvox.strip
    )
    lead.update_column(:jabvox_campaign_id, @import_campaign.id) # rubocop:disable Rails/SkipsModelValidations
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def find_contact_by_phone(phone)
    return nil if phone.blank?

    @account.contacts.find_by(phone_number: phone)
  end

  def find_contact_by_email(email)
    return nil if email.blank?

    @account.contacts.find_by(email: email)
  end

  def normalized_email(value)
    email = value.to_s.strip.downcase
    email.present? && email.match?(Devise.email_regexp) ? email : nil
  end

  def create_contact(row, phone)
    email = normalized_email(mapped_value(row, 'email'))
    contact = @account.contacts.new(
      name: mapped_value(row, 'name').to_s.presence || 'Sin nombre',
      contact_type: :lead,
      # Initialize jsonb columns so downstream code that assumes {} never breaks
      # (before_validation normalization may not run when we skip validation).
      additional_attributes: {}, custom_attributes: {}
    )
    contact.phone_number = phone if phone.present?
    contact.email = email if email.present?
    begin
      save_contact(contact)
      contact
    rescue ActiveRecord::RecordInvalid
      # Lost a race / a matching contact already exists → reuse it instead of
      # creating a duplicate. Falls back to a validation-free insert only if we
      # genuinely can't find the existing one.
      find_contact_by_phone(phone) || find_contact_by_email(email) ||
        contact.tap { |c| c.save!(validate: false) }
    end
  end

  # Applies the field mapping. A lead is backed by a Contact, so standard fields
  # map to the contact (direct columns, additional_attributes keys, or social
  # profiles); 'custom' fields go to the lead's custom columns row. Notes are
  # never touched here.
  def apply_mapping(lead, row)
    contact = lead.contact
    custom = {}
    attrs = (contact.additional_attributes || {}).dup
    socials = (attrs['social_profiles'] || {}).dup

    @mapping.each do |external_col, target|
      kind, key = parse_target(target)
      next if kind.blank?

      value = row[external_col]
      case kind
      when 'name' then contact.name = value.to_s if value.present?
      when 'last_name' then contact.last_name = value.to_s if value.present?
      when 'email' then assign_email(contact, value)
      when 'phone' then assign_phone(contact, value)
      when 'custom' then custom[key] = value if key.present?
      when /\Aattr:(.+)\z/ then assign_attr(attrs, Regexp.last_match(1), value)
      when /\Asocial:(.+)\z/ then socials[Regexp.last_match(1)] = value.to_s if value.present?
      end
    end

    # Los leads importados desde una BD externa siempre son personas: si el
    # contacto aún no tiene tipo definido, lo dejamos en "persona" por defecto.
    attrs['jabvox_contact_type'] = 'persona' if attrs['jabvox_contact_type'].blank?

    attrs['social_profiles'] = socials if socials.any?
    contact.additional_attributes = attrs
    save_contact(contact)
    lead.save!
    # Tag with the connection-named campaign (runs on both create and update so
    # a re-sync backfills leads imported before this was added).
    assign_import_campaign(lead)
    apply_custom_fields(lead, custom) if custom.any?
  end

  # Canonical parse of a mapping target. Supports both shapes:
  #   { 'kind' => 'phone', 'target' => 'phone' }  (current)
  #   'phone'                                       (legacy string)
  # Returns [kind, key].
  def parse_target(target)
    if target.is_a?(Hash)
      [target['kind'] || target['type'], target['target'] || target['key']]
    else
      [target.to_s, target.to_s]
    end
  end

  # Saves the contact tolerantly. Validations run first (uniqueness +
  # normalization). If ONLY a uniqueness error blocks a NEW contact, we don't
  # force a duplicate with validate:false — that would defeat dedup; instead we
  # let the caller keep the record it has (already-persisted contacts just save
  # their changes). Any other invalid value still persists so a row is never
  # dropped for a missing/odd field.
  def save_contact(contact)
    contact.save!
  rescue ActiveRecord::RecordInvalid => e
    only_uniqueness = e.record.errors.details.values.flatten.all? { |d| d[:error] == :taken }
    # A brand-new contact blocked purely by uniqueness means a match already
    # exists — skip the forced insert rather than create a duplicate.
    raise e if only_uniqueness && contact.new_record?

    contact.save!(validate: false)
  end

  def assign_email(contact, value)
    email = value.to_s.strip
    contact.email = email.downcase if email.present? && email.match?(Devise.email_regexp)
  end

  def assign_phone(contact, value)
    phone = normalized_phone(value)
    contact.phone_number = phone if phone.present?
  end

  # Writes custom-field values for the lead. Values are written to BOTH stores so
  # every screen sees them:
  #   - lead.custom_fields_jabvox : the jsonb the lead DETAIL view renders
  #     (show.json.jbuilder) and that manual edits update — this is what the user
  #     sees per lead.
  #   - jabvox_custom_table_rows.data_jabvox : the "leads" custom-table row used
  #     by table-oriented views.
  # Each value is cast to the column's declared type. Keys are the column
  # name_jabvox, matching how the sanitizer/detail view key their data.
  def apply_custom_fields(lead, custom)
    table = @account.jabvox_custom_tables.find_by(linked_to_jabvox: 'leads')
    return unless table

    types = table.jabvox_custom_columns.pluck(:name_jabvox, :column_type_jabvox).to_h
    casted = custom.each_with_object({}) do |(key, value), acc|
      next unless types.key?(key) # only known columns, so the detail view can label them

      acc[key] = cast_value(value, types[key])
    end
    return if casted.empty?

    # Detail view + manual edits read this jsonb on the lead itself.
    lead.update!(custom_fields_jabvox: (lead.custom_fields_jabvox || {}).merge(casted))

    # Table-oriented views read the custom-table row.
    row = lead.jabvox_custom_table_rows.find_or_initialize_by(jabvox_custom_table: table)
    row.data_jabvox = (row.data_jabvox || {}).merge(casted)
    row.save!
  end

  # Casts an imported value to the declared custom-column type for correct storage.
  # Unparseable numbers/dates become nil instead of raising, so a single bad row
  # never aborts the whole sync.
  def cast_value(value, type)
    return nil if value.nil? || value == ''

    case type
    when 'integer' then Integer(value.to_s.strip.delete(','), exception: false)
    when 'float' then Float(value.to_s.strip.delete(',')) rescue nil
    when 'boolean' then cast_boolean(value)
    when 'date' then cast_date(value)
    else value.to_s
    end
  end

  def cast_boolean(value)
    [true, 'true', 1, '1', 't', 'yes', 'sí', 'si', 'x'].include?(
      value.is_a?(String) ? value.strip.downcase : value
    )
  end

  # Accepts ISO, "DD/MM/YYYY" and "DD/MM/YYYY hh:mm[ am/pm]" (SuiteCRM formats).
  # Stored as ISO date string; returns nil if nothing parses.
  def cast_date(value)
    str = value.to_s.strip
    return nil if str.blank?
    return str if str.match?(/\A\d{4}-\d{2}-\d{2}/)

    m = str.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})})
    return nil unless m

    Date.new(m[3].to_i, m[2].to_i, m[1].to_i).iso8601
  rescue ArgumentError
    nil
  end

  # Writes an additional_attributes key only when the source has a value.
  def assign_attr(attrs, key, value)
    attrs[key] = value.to_s if value.present?
  end

  # Value of the mapped external column for a given standard field kind.
  def mapped_value(row, kind)
    col, = @mapping.find do |_ext, target|
      k, = parse_target(target)
      k == kind
    end
    col ? row[col] : nil
  end

  # Best-effort E.164 normalization; returns nil if it can't be made valid.
  # With a configured country prefix (e.g. "57") it covers the three shapes
  # external DBs bring: "+573207038072" (kept), "573207038072" (adds +),
  # "3207038072" (adds +57). Local numbers with leading zeros are trimmed.
  def normalized_phone(value)
    digits = value.to_s.gsub(/[^\d+]/, '')
    return nil if digits.blank?

    unless digits.start_with?('+')
      prefix = @source.phone_prefix_jabvox.to_s.gsub(/\D/, '')
      if prefix.present?
        digits = digits.sub(/\A0+/, '')
        # Already carries the country code when it starts with the prefix AND
        # is longer than a bare local number could be with it prepended.
        digits = if digits.start_with?(prefix) && digits.length > prefix.length + 6
                   "+#{digits}"
                 else
                   "+#{prefix}#{digits}"
                 end
      else
        digits = "+#{digits}"
      end
    end
    digits.match?(/\A\+[1-9]\d{1,14}\z/) ? digits : nil
  end
end
