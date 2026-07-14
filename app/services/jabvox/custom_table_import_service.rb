# frozen_string_literal: true

# Imports a custom table (its definition + columns, NOT its row data) from the
# JSON produced by the export endpoint. Creates a new multi-record table with
# the given columns, or upserts columns into an existing table matched by name.
#
# Security model (identical spirit to TypificationsImportService):
#   - The file is pure DATA. Nothing is executed.
#   - Every field is coerced through a strict whitelist before touching the DB:
#     unknown keys are dropped, types are validated, options/conditions are
#     sanitized. No mass assignment, no extra columns, no code paths.
#   - The system "Leads" table can never be created/overwritten via import.
#   - All-or-nothing: any invalid column rolls the whole import back.
module Jabvox
  class CustomTableImportService
    MAX_COLUMNS = 300
    MAX_OPTIONS = 500
    MAX_OPTION_LEN = 300     # per option/trigger string (defends against giant values)
    MAX_PAYLOAD_BYTES = 1_000_000 # 1 MB of JSON is far more than any real definition
    NAME_MAX = 150
    LABEL_MAX = 200
    DESC_MAX = 1_000
    VALID_TYPES = JabvoxCustomColumn::COLUMN_TYPES # text/textarea/integer/float/boolean/date/select/multiselect
    VALID_KINDS = %w[single multi].freeze

    Result = Struct.new(:table, :created_columns, :updated_columns, :errors) do
      def valid?
        errors.empty?
      end
    end

    def initialize(account, payload)
      @account = account
      @payload = payload
    end

    def call
      return err('El archivo supera el tamaño máximo permitido.') if payload_too_big?

      table_attrs = extract_table
      return err('Formato inválido: falta el objeto "table".') if table_attrs.nil?

      name = sanitize_str(table_attrs['name_jabvox'], NAME_MAX)
      return err('La tabla necesita un nombre.') if name.blank?
      return err('No se puede importar sobre la tabla del sistema "Leads".') if name.casecmp('leads').zero?

      columns = extract_columns
      return err('El archivo no contiene columnas.') if columns.blank?
      return err("Máximo #{MAX_COLUMNS} columnas por importación.") if columns.size > MAX_COLUMNS

      created = 0
      updated = 0
      table = nil
      errors = []

      ActiveRecord::Base.transaction do
        table = upsert_table(name, table_attrs)
        seen = {}
        columns.each_with_index do |raw, idx|
          col_attrs, error = sanitize_column(raw, idx)
          if error
            errors << error
            next
          end
          # Duplicate name within the same file → keep the first, skip the rest.
          next if seen.key?(col_attrs[:name_jabvox])

          seen[col_attrs[:name_jabvox]] = true
          existing = table.jabvox_custom_columns.find_by(name_jabvox: col_attrs[:name_jabvox])
          if existing
            existing.update!(col_attrs)
            updated += 1
          else
            table.jabvox_custom_columns.create!(col_attrs)
            created += 1
          end
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      return Result.new(nil, 0, 0, errors) if errors.any?

      Result.new(table, created, updated, [])
    rescue ActiveRecord::RecordInvalid => e
      err("No se pudo importar: #{e.record.errors.full_messages.join(', ')}")
    end

    private

    def err(message)
      Result.new(nil, 0, 0, [message])
    end

    # Rejects oversized payloads before doing any work — a cheap DoS guard that
    # doesn't depend on the frontend's 2 MB check (the endpoint can be called
    # directly). Serializing to measure is bounded and safe.
    def payload_too_big?
      JSON.generate(@payload).bytesize > MAX_PAYLOAD_BYTES
    rescue StandardError
      true # unserializable / circular → treat as invalid
    end

    def extract_table
      root = @payload.is_a?(Hash) ? @payload.with_indifferent_access : nil
      return nil unless root

      t = root['table'] || root[:table]
      t.is_a?(Hash) ? t.stringify_keys : nil
    end

    def extract_columns
      root = @payload.with_indifferent_access
      cols = root['columns'] || (root['table'].is_a?(Hash) ? root['table']['columns'] : nil)
      cols.is_a?(Array) ? cols : []
    end

    # Creates the table if missing, else reuses the one with that name. Always a
    # non-system table; kind is validated. Never touches the Leads table.
    def upsert_table(name, attrs)
      kind = VALID_KINDS.include?(attrs['kind_jabvox'].to_s) ? attrs['kind_jabvox'].to_s : 'multi'
      table = @account.jabvox_custom_tables
                      .where(linked_to_jabvox: nil)
                      .find_by('LOWER(name_jabvox) = ?', name.downcase)
      if table
        table.update!(description_jabvox: sanitize_str(attrs['description_jabvox'], DESC_MAX), kind_jabvox: kind)
        table
      else
        @account.jabvox_custom_tables.create!(
          name_jabvox: name,
          description_jabvox: sanitize_str(attrs['description_jabvox'], DESC_MAX),
          kind_jabvox: kind,
          linked_to_jabvox: nil
        )
      end
    end

    # Returns [attrs_hash, nil] or [nil, error_message]. Strict whitelist.
    def sanitize_column(raw, idx)
      return [nil, "Columna #{idx + 1}: formato inválido."] unless raw.is_a?(Hash)

      r = raw.with_indifferent_access
      name = sanitize_key(r['name_jabvox'])
      return [nil, "Columna #{idx + 1}: nombre interno inválido."] if name.blank?

      label = sanitize_str(r['label_jabvox'], LABEL_MAX)
      label = name if label.blank?

      type = r['column_type_jabvox'].to_s
      type = 'text' unless VALID_TYPES.include?(type)

      options = sanitize_options(r['options_jabvox'])
      depends_on = sanitize_key(r['depends_on_jabvox'])
      depends_on = nil if depends_on.blank?
      show_when = depends_on ? sanitize_options(r['show_when_jabvox']) : []

      [{
        name_jabvox: name,
        label_jabvox: label,
        column_type_jabvox: type,
        options_jabvox: options,
        required_jabvox: [true, 'true', 1, '1'].include?(r['required_jabvox']),
        position_jabvox: idx,
        depends_on_jabvox: depends_on,
        show_when_jabvox: show_when
      }, nil]
    end

    # Options / trigger values: only SCALAR entries (string/number/bool) are
    # accepted — nested hashes/arrays are dropped, never flattened into giant
    # strings. Each value is trimmed to MAX_OPTION_LEN and the list is capped.
    def sanitize_options(value)
      return [] unless value.is_a?(Array)

      value
        .reject { |v| v.is_a?(Hash) || v.is_a?(Array) }
        .map { |v| v.to_s.strip[0, MAX_OPTION_LEN].to_s }
        .reject(&:blank?)
        .uniq
        .first(MAX_OPTIONS)
    end

    # Internal column name: same slug rule used everywhere else ([a-z0-9_]).
    # Never let a non-scalar through (a Hash#to_s could be huge/unexpected).
    def sanitize_key(value)
      return '' if value.is_a?(Hash) || value.is_a?(Array)

      value.to_s.strip.downcase.gsub(/[^a-z0-9_]/, '')
    end

    # Free text (name/label/description). Non-scalar input yields "" instead of a
    # Hash/Array string dump. Always length-bounded.
    def sanitize_str(value, max)
      return '' if value.is_a?(Hash) || value.is_a?(Array)

      value.to_s.strip[0, max].to_s
    end
  end
end
