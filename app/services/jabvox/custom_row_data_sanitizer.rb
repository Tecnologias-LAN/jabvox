# Sanitizes a user-supplied data hash for a custom table row against that
# table's defined columns. This is the single security choke point for row
# data: it drops any key that is not a real column of the table, coerces each
# value to its column type, and enforces required columns — so nothing
# arbitrary or malformed ever reaches the JSONB payload.
#
# Usage:
#   result = Jabvox::CustomRowDataSanitizer.new(table, params_hash).call
#   result.valid?  # => true/false
#   result.data    # => sanitized hash (only known columns, coerced values)
#   result.errors  # => array of human-readable messages
class Jabvox::CustomRowDataSanitizer
  Result = Struct.new(:data, :errors) do
    def valid?
      errors.empty?
    end
  end

  def initialize(table, raw_data)
    @table = table
    @raw = raw_data.is_a?(Hash) ? raw_data.stringify_keys : {}
  end

  def call
    data = {}
    errors = []

    columns.each do |column|
      # A column hidden by its condition (its controlling answer doesn't match)
      # is neither required nor stored — so conditional questions never block a
      # save and no stale answers linger from a path the user didn't take.
      next unless column.visible_for?(@raw)

      raw_value = @raw[column.name_jabvox]
      coerced, error = column.coerce(raw_value)

      if error
        errors << error
        next
      end

      if blank_value?(coerced)
        errors << "#{column.label_jabvox}: is required" if column.required_jabvox
        next
      end

      data[column.name_jabvox] = coerced
    end

    Result.new(data, errors)
  end

  private

  def columns
    @columns ||= @table.jabvox_custom_columns.ordered
  end

  # Multiselect stores an array; empty array counts as blank.
  def blank_value?(value)
    value.nil? || value == '' || (value.is_a?(Array) && value.empty?)
  end
end
