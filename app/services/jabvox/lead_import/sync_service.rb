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
    offset = 0
    MAX_PAGES.times do
      result = adapter.execute("#{select_sql} LIMIT #{PAGE_SIZE} OFFSET #{offset}",
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

    return "SELECT * FROM #{q.call(main)}" if joins.empty?

    select_parts = ["#{q.call(main)}.*"]
    join_parts = []
    joins.each do |rel|
      tbl = rel['table']
      als = safe_alias(rel['alias'].presence || tbl)
      local = rel['local_key']
      foreign = rel['foreign_key']
      next if tbl.blank? || local.blank? || foreign.blank?

      # Expose related columns as "als.col" via per-column aliases.
      column_names(adapter, tbl).each do |col|
        select_parts << "#{q.call(als)}.#{q.call(col)} AS #{q.call("#{als}.#{col}")}"
      end
      join_parts << "LEFT JOIN #{q.call(tbl)} AS #{q.call(als)} " \
                    "ON #{q.call(als)}.#{q.call(foreign)} = #{q.call(main)}.#{q.call(local)}"
    end

    "SELECT #{select_parts.join(', ')} FROM #{q.call(main)} #{join_parts.join(' ')}"
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

  # Finds a contact by phone (mapped) or creates one with whatever the row brings.
  def build_lead_for(row)
    phone = normalized_phone(mapped_value(row, 'phone'))
    contact = find_contact_by_phone(phone)
    contact ||= create_contact(row, phone)
    @account.jabvox_leads.find_or_create_by!(contact: contact)
  end

  def find_contact_by_phone(phone)
    return nil if phone.blank?

    @account.contacts.find_by(phone_number: phone)
  end

  def create_contact(row, phone)
    contact = @account.contacts.new(
      name: mapped_value(row, 'name').to_s.presence || 'Sin nombre',
      contact_type: :lead,
      # Initialize jsonb columns so downstream code that assumes {} never breaks
      # (before_validation normalization may not run when we skip validation).
      additional_attributes: {}, custom_attributes: {}
    )
    contact.phone_number = phone if phone.present?
    email = mapped_value(row, 'email').to_s.strip
    contact.email = email.downcase if email.present? && email.match?(Devise.email_regexp)
    save_contact(contact)
    contact
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
      when /\Aattr:(.+)\z/ then attrs[Regexp.last_match(1)] = value.to_s if value.present?
      when /\Asocial:(.+)\z/ then socials[Regexp.last_match(1)] = value.to_s if value.present?
      end
    end

    attrs['social_profiles'] = socials if socials.any?
    contact.additional_attributes = attrs
    save_contact(contact)
    lead.save!
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

  # Saves the contact tolerantly: try with validations first (so uniqueness and
  # normalization run); if an invalid value blocks it, persist what we have so a
  # row is never dropped for missing/odd fields.
  def save_contact(contact)
    contact.save!
  rescue ActiveRecord::RecordInvalid
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

  # Writes custom-field values into the lead's row of the "leads" custom table,
  # casting each value to the column's declared type.
  def apply_custom_fields(lead, custom)
    table = @account.jabvox_custom_tables.find_by(linked_to_jabvox: 'leads')
    return unless table

    types = table.jabvox_custom_columns.pluck(:name_jabvox, :column_type_jabvox).to_h
    casted = custom.each_with_object({}) do |(key, value), acc|
      acc[key] = cast_value(value, types[key])
    end
    row = lead.jabvox_custom_table_rows.find_or_initialize_by(jabvox_custom_table: table)
    row.data_jabvox = (row.data_jabvox || {}).merge(casted)
    row.save!
  end

  # Casts an imported value to the declared custom-column type for correct storage.
  def cast_value(value, type)
    return nil if value.nil?

    case type
    when 'integer' then Integer(value, exception: false)
    when 'float' then Float(value, exception: false)
    when 'boolean' then [true, 'true', 1, '1', 't', 'yes', 'sí', 'si'].include?(value.is_a?(String) ? value.downcase : value)
    else value.to_s
    end
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
  def normalized_phone(value)
    digits = value.to_s.gsub(/[^\d+]/, '')
    return nil if digits.blank?

    digits = "+#{digits}" unless digits.start_with?('+')
    digits.match?(/\A\+[1-9]\d{1,14}\z/) ? digits : nil
  end
end
