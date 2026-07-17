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

    # Sentinel the pickers send to mean "the field is empty / missing" — it can
    # be selected alone or together with real values (OR).
    EMPTY_VALUE = '__empty__'

    # Column definitions and imported data sometimes drift on the "_c" suffix
    # (column "estado_pedido_c" while the leads store "estado_pedido", or the
    # inverse). Filtering, value discovery and search always consider BOTH
    # variants so a defined field keeps working no matter where the data lives.
    def key_variants(key)
      [key, key.sub(/_c\z/, ''), "#{key}_c"].uniq.reject(&:blank?)
    end

    # Applies { field_key => value } filters onto an AR relation of jabvox_leads.
    def apply(leads, custom)
      return leads unless custom.respond_to?(:each_pair)

      custom.each_pair do |raw_key, value|
        key = sanitize_key(raw_key)
        next if key.blank?

        options = list_values(value)
        if options
          leads = apply_options(leads, key, options)
        elsif value.to_s.strip == EMPTY_VALUE
          empty_cond, empty_binds = empty_condition(key)
          leads = leads.where(empty_cond, *empty_binds)
        elsif value.to_s.strip.present?
          variants = key_variants(key)
          sql = variants.map { 'jabvox_leads.custom_fields_jabvox ->> ? ILIKE ?' }.join(' OR ')
          like = "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
          leads = leads.where(sql, *variants.flat_map { |v| [v, like] })
        end
      end
      leads
    end

    # List-mode dispatch: real values, the empty sentinel, or both (OR).
    def apply_options(leads, key, options)
      wants_empty = options.include?(EMPTY_VALUE)
      values = options - [EMPTY_VALUE]
      return leads if values.empty? && !wants_empty

      empty_cond, empty_binds = empty_condition(key)
      return leads.where(empty_cond, *empty_binds) if values.empty?
      return apply_multi_value(leads, key, values) unless wants_empty

      value_sql, value_binds = multi_value_condition(key, values)
      leads.where("(#{value_sql}) OR (#{empty_cond})", *value_binds, *empty_binds)
    end

    # Field counts as empty when EVERY key variant is missing, JSON null,
    # blank/whitespace text, or an empty array.
    def empty_condition(key)
      variants = key_variants(key)
      per_key =
        "(jabvox_leads.custom_fields_jabvox ->> ? IS NULL " \
        "OR btrim(jabvox_leads.custom_fields_jabvox ->> ?) = '' " \
        "OR jabvox_leads.custom_fields_jabvox ->> ? = '[]')"
      sql = "(#{variants.map { per_key }.join(' AND ')})"
      [sql, variants.flat_map { |v| [v, v, v] }]
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
      sql, binds = multi_value_condition(key, options)
      leads.where(sql, *binds)
    end

    # [sql, binds] for the multi-value condition, reusable inside OR groups.
    # Matching is case- and whitespace-insensitive on both sides (imported data
    # often differs from the configured options only in casing/trailing spaces)
    # and is checked against every key variant (OR).
    def multi_value_condition(key, options)
      normalized = options.map { |o| o.to_s.strip.downcase }
      placeholders = Array.new(normalized.length, '?').join(', ')
      per_key_sql =
        "(lower(btrim(jabvox_leads.custom_fields_jabvox ->> ?)) IN (#{placeholders})) " \
        "OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(" \
        "CASE WHEN jsonb_typeof(jabvox_leads.custom_fields_jabvox -> ?) = 'array' " \
        "THEN jabvox_leads.custom_fields_jabvox -> ? ELSE '[]'::jsonb END) AS elem " \
        "WHERE lower(btrim(elem)) IN (#{placeholders}))"

      variants = key_variants(key)
      sql = variants.map { "(#{per_key_sql})" }.join(' OR ')
      binds = variants.flat_map { |v| [v, *normalized, v, v, *normalized] }
      [sql, binds]
    end

    # Every custom-field key actually PRESENT in the account's leads data,
    # regardless of whether a column is defined for it. This is what makes the
    # pickers show every real field even when the column definitions and the
    # stored keys drifted apart (e.g. columns imported as "seccion_c" while the
    # data was saved under "seccion"). Only safe keys ([a-z0-9_]) are returned —
    # they're used as jsonb keys and shown in the UI.
    def data_keys(account, limit: 200)
      sql = <<~SQL.squish
        SELECT DISTINCT jsonb_object_keys(jabvox_leads.custom_fields_jabvox) AS k
        FROM jabvox_leads
        WHERE jabvox_leads.account_id = :aid
          AND jabvox_leads.custom_fields_jabvox <> '{}'::jsonb
        ORDER BY k
        LIMIT :lim
      SQL
      JabvoxLead.connection.select_values(
        JabvoxLead.sanitize_sql_array([sql, { aid: account.id, lim: limit }])
      ).select { |k| k.match?(/\A[a-z0-9_]+\z/) }
    end

    # Server-side option search for ONE key: distinct values matching `q`
    # (case-insensitive substring), so high-cardinality fields — whose base
    # option list is capped — can still offer every value through the picker's
    # search box. Handles scalar and array storage like distinct_values.
    def distinct_values_search(account, key, query, limit: 50)
      safe_key = sanitize_key(key)
      return [] if safe_key.blank?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
      key_variants(safe_key).flat_map do |variant|
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
          WHERE val IS NOT NULL AND val <> '' AND val ILIKE :q
          ORDER BY val
          LIMIT :lim
        SQL
        JabvoxLead.connection.select_values(
          JabvoxLead.sanitize_sql_array([sql, { k: variant, aid: account.id, q: like, lim: limit }])
        )
      end.uniq.sort.first(limit)
    end

    # Distinct values present across an account's leads for each custom-field key,
    # so the pickers can show a checkbox list even for plain-text fields. Handles
    # scalar values and jsonb arrays (flattened). Returns { key => [values] },
    # each capped at `limit`.
    def distinct_values(account, keys, limit: 200)
      return {} if keys.blank?

      # Only query variant keys that actually exist in the data (avoids 2-3x
      # queries per field for variants that hold nothing).
      present = data_keys(account, limit: 1000)
      keys.each_with_object({}) do |key, acc|
        safe_key = sanitize_key(key)
        next if safe_key.blank?

        variants = key_variants(safe_key).select { |v| present.include?(v) }
        variants = [safe_key] if variants.empty?
        acc[key] = variants.flat_map { |v| distinct_values_for_key(account, v, limit) }
                           .uniq.sort.first(limit)
      end
    end

    # Distinct values of ONE exact jsonb key (scalar + array storage).
    def distinct_values_for_key(account, key, limit)
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
      JabvoxLead.connection.select_values(
        JabvoxLead.sanitize_sql_array([sql, { k: key.to_s, aid: account.id, lim: limit }])
      )
    end
  end
end
