# Expands a lead's custom fields (stored inline in jabvox_leads.custom_fields_jabvox,
# a jsonb blob) into one real column per defined custom field, so the external DB
# gets a proper column (e.g. seccion_c, alias_c, tienda_activa_c) instead of a
# single opaque jsonb column.
#
# The source of truth for WHICH columns exist is the account's single lead-linked
# custom table (JabvoxCustomTable.for_leads) and its ordered JabvoxCustomColumns —
# NOT the raw jsonb keys (which are heterogeneous across historical imports).
#
# When reading a lead's value for a column we tolerate legacy keys: some old rows
# stored the value under a key without the "_c" suffix (e.g. "seccion" for the
# column "seccion_c"), so we probe a few equivalent keys before giving up.
class Jabvox::ExternalExport::LeadCustomColumns
  # Maps a JabvoxCustomColumn type to the storage type understood by WriteAdapter#sql_type.
  TYPE_MAP = {
    'integer' => :integer,
    'float' => :float,
    'boolean' => :boolean,
    'date' => :date,
    'text' => :string,
    'textarea' => :string,
    'select' => :string,
    'multiselect' => :string # stored as a JSON string of the selected values
  }.freeze

  def initialize(account)
    @account = account
  end

  # [{ name:, type: }] — one entry per defined custom field, for the schema builder.
  # Empty when the account has no lead-linked custom table.
  def column_defs
    custom_columns.map do |col|
      { name: col.name_jabvox, type: TYPE_MAP.fetch(col.column_type_jabvox, :string) }
    end
  end

  # { name_jabvox => value } for a single lead, one entry per defined column.
  # Missing values are nil so every exported lead shares the SAME column set
  # (keeps the batch upsert grouping stable). Values are read with a legacy-key
  # fallback and lightly normalized (arrays -> JSON string).
  def values_for(lead)
    raw = lead.custom_fields_jabvox.is_a?(Hash) ? lead.custom_fields_jabvox : {}
    custom_columns.each_with_object({}) do |col, acc|
      acc[col.name_jabvox] = normalize(lookup(raw, col.name_jabvox))
    end
  end

  # True when there is at least one defined custom column to expand.
  def any?
    custom_columns.any?
  end

  private

  def custom_columns
    return @custom_columns if defined?(@custom_columns)

    table = @account.jabvox_custom_tables.for_leads.first
    cols = table ? table.jabvox_custom_columns.ordered.to_a : []
    # Never let a custom field named like a secret (password, token…) reintroduce
    # sensitive data past the column-name filter applied to real columns.
    @custom_columns = cols.reject { |c| Jabvox::ExternalExport::Catalog.sensitive?(c.name_jabvox) }
  end

  # Probes the canonical key first, then legacy variants used by older imports:
  # the same name without a trailing "_c", and (defensively) with one added.
  def lookup(raw, name)
    candidates = [name]
    candidates << name.sub(/_c\z/, '') if name.end_with?('_c')
    candidates << "#{name}_c" unless name.end_with?('_c')
    key = candidates.find { |k| raw.key?(k) && !blank?(raw[k]) }
    key ? raw[key] : nil
  end

  # Arrays (multiselect) become a JSON string so they fit a TEXT column; scalars
  # pass through unchanged (the DB column type coerces them on insert).
  def normalize(value)
    value.is_a?(Array) ? value.to_json : value
  end

  def blank?(value)
    value.nil? || value == '' || (value.is_a?(Array) && value.empty?)
  end
end
