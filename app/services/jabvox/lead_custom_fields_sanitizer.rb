# Sanitizes a user-supplied custom-fields hash for a lead against the
# account's lead-linked custom table definitions. Mirrors what
# CustomRowDataSanitizer does for table rows: unknown keys are dropped,
# values are coerced to their column type, and blank values remove the key
# (erroring instead when the column is required). The result is the FULL
# merged hash to store, so callers replace custom_fields_jabvox with it.
#
# Accounts with no lead-linked table (no definitions) get a passthrough
# merge, preserving the historical behavior for data written before
# definitions existed.
#
# Usage:
#   result = Jabvox::LeadCustomFieldsSanitizer.new(account, lead.custom_fields_jabvox, params).call
#   result.valid?  # => true/false
#   result.data    # => merged hash ready to store
#   result.errors  # => array of human-readable messages
class Jabvox::LeadCustomFieldsSanitizer
  Result = Struct.new(:data, :errors) do
    def valid?
      errors.empty?
    end
  end

  def initialize(account, existing, incoming)
    @account = account
    @existing = existing.is_a?(Hash) ? existing.stringify_keys : {}
    @incoming = incoming.is_a?(Hash) ? incoming.stringify_keys : {}
  end

  def call
    return Result.new(@existing.merge(@incoming), []) if columns_by_name.nil?

    merged = @existing.dup
    errors = []

    @incoming.each do |key, raw_value|
      column = columns_by_name[key]
      next if column.nil?

      if blank_value?(raw_value)
        if column.required_jabvox
          errors << "#{column.label_jabvox}: is required"
        else
          merged.delete(key)
        end
        next
      end

      coerced, error = column.coerce(raw_value)
      if error
        errors << error
        next
      end

      merged[key] = coerced
    end

    Result.new(merged, errors)
  end

  private

  # nil when the account has no lead-linked table at all (passthrough mode);
  # a name=>column hash otherwise.
  def columns_by_name
    return @columns_by_name if defined?(@columns_by_name)

    table = @account.jabvox_custom_tables.for_leads.first
    @columns_by_name = table&.jabvox_custom_columns&.index_by(&:name_jabvox)
  end

  def blank_value?(value)
    value.nil? || value == ''
  end
end
