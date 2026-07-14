# Shared logic for filtering leads by their custom fields (custom_fields_jabvox
# jsonb) and for discovering the selectable values of each field. Used by both
# the bulk-WhatsApp lead picker and the dialer campaign filters so the behaviour
# — and the SQL-injection safety — lives in ONE place.
#
# A filter value may arrive as:
#   - String  -> case-insensitive substring match (free text).
#   - Array   -> match ANY of the values (OR). ["Esmeralda","Diamante"]
#   - Hash with numeric-index keys ({"0"=>"Esmeralda","1"=>"Diamante"}) -> same
#     as an Array. This is how axios 1.x serializes arrays in the query string
#     and how Rails then parses them; without handling it the multi-select
#     filter silently matched nothing.
#
# For list values it matches BOTH storage shapes of the field:
#   - scalar jsonb ("Esmeralda")          -> equals one of the values
#   - array  jsonb (["Belleza","Salud"])  -> overlaps the values
#
# Security: the jsonb key is sanitized to [a-z0-9_]; every user value is passed
# as a bind parameter, never interpolated into SQL.
module Jabvox
  module LeadCustomFilter
    module_function

    # Applies { field_key => value } filters onto an AR relation of jabvox_leads.
    def apply(leads, custom)
      return leads unless custom.respond_to?(:each_pair)

      custom.each_pair do |raw_key, value|
        key = sanitize_key(raw_key)
        next if key.blank?

        options = list_values(value)
        if options
          next if options.empty?

          leads = apply_multi_value(leads, key, options)
        else
          next if value.to_s.strip.blank?

          leads = leads.where('jabvox_leads.custom_fields_jabvox ->> ? ILIKE ?', key,
                              "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%")
        end
      end
      leads
    end

    def sanitize_key(raw_key)
      raw_key.to_s.downcase.gsub(/[^a-z0-9_]/, '')
    end

    # Returns the list of values for a list-style filter, or nil for plain text.
    # Any Array/index-Hash is list mode (returns [] when empty, so the caller
    # skips it) — it never falls back to substring matching.
    def list_values(value)
      hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
      values =
        if value.is_a?(Array)
          value
        elsif hash.is_a?(Hash) && numeric_index_keys?(hash)
          hash.keys.sort_by(&:to_i).map { |k| hash[k] }
        end
      return nil if values.nil?

      values.map(&:to_s).reject(&:blank?).uniq
    end

    # True for an empty hash or one whose keys are all integers ("0","1"…).
    def numeric_index_keys?(hash)
      hash.empty? || hash.keys.all? { |k| k.to_s.match?(/\A\d+\z/) }
    end

    # Matches a sanitized key against ANY of `options` (scalar equality OR jsonb
    # array overlap). Placeholders are generated, values are all binds.
    def apply_multi_value(leads, key, options)
      placeholders = Array.new(options.length, '?').join(', ')
      scalar = "jabvox_leads.custom_fields_jabvox ->> ? IN (#{placeholders})"
      array_overlap =
        "(jsonb_typeof(jabvox_leads.custom_fields_jabvox -> ?) = 'array' " \
        "AND jsonb_exists_any(jabvox_leads.custom_fields_jabvox -> ?, array[#{placeholders}]::text[]))"

      sql = "(#{scalar}) OR #{array_overlap}"
      binds = [key, *options, key, key, *options]
      leads.where(sql, *binds)
    end

    # Distinct values present across an account's leads for each custom-field key,
    # so the pickers can show a checkbox list even for plain-text fields. Handles
    # scalar values and jsonb arrays (flattened). Returns { key => [values] },
    # each capped at `limit`.
    def distinct_values(account, keys, limit: 200)
      return {} if keys.blank?

      keys.each_with_object({}) do |key, acc|
        safe_key = sanitize_key(key)
        next if safe_key.blank?

        sql = <<~SQL.squish
          SELECT DISTINCT val FROM (
            SELECT jabvox_leads.custom_fields_jabvox ->> :k AS val
            FROM jabvox_leads
            WHERE jabvox_leads.account_id = :aid
              AND jsonb_typeof(jabvox_leads.custom_fields_jabvox -> :k) <> 'array'
            UNION
            SELECT jsonb_array_elements_text(jabvox_leads.custom_fields_jabvox -> :k) AS val
            FROM jabvox_leads
            WHERE jabvox_leads.account_id = :aid
              AND jsonb_typeof(jabvox_leads.custom_fields_jabvox -> :k) = 'array'
          ) t
          WHERE val IS NOT NULL AND val <> ''
          ORDER BY val
          LIMIT :lim
        SQL
        acc[key] = JabvoxLead.connection.select_values(
          JabvoxLead.sanitize_sql_array([sql, { k: key.to_s, aid: account.id, lim: limit }])
        )
      end
    end
  end
end
