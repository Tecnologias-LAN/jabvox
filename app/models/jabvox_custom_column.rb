# == Schema Information
#
# Table name: jabvox_custom_columns
#
#  id                     :bigint           not null, primary key
#  column_type_jabvox     :string           default("text"), not null
#  depends_on_jabvox      :string
#  label_jabvox           :string           not null
#  name_jabvox            :string           not null
#  options_jabvox         :jsonb
#  position_jabvox        :integer          default(0), not null
#  required_jabvox        :boolean          default(FALSE), not null
#  show_when_jabvox       :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  jabvox_custom_table_id :bigint           not null
#
# Indexes
#
#  idx_jabvox_custom_columns_table_name                   (jabvox_custom_table_id,name_jabvox) UNIQUE
#  index_jabvox_custom_columns_on_jabvox_custom_table_id  (jabvox_custom_table_id)
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_custom_table_id => jabvox_custom_tables.id)
#
class JabvoxCustomColumn < ApplicationRecord
  # text     : short single-line text        textarea : long multi-line text
  # integer/float/boolean/date               select   : one value from options_jabvox
  # multiselect : many values from options_jabvox (stored as an array)
  COLUMN_TYPES = %w[text textarea integer float boolean date select multiselect].freeze

  belongs_to :jabvox_custom_table

  validates :name_jabvox, presence: true, uniqueness: { scope: :jabvox_custom_table_id }
  validates :label_jabvox, presence: true
  validates :column_type_jabvox, inclusion: { in: COLUMN_TYPES }

  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }

  # Conditional display: this column is visible only when the answer to the
  # column named `depends_on_jabvox` (in the same table) matches ANY value in
  # `show_when_jabvox`. Columns with no dependency are always visible.
  #
  #   visible_for?({ 'tipo_acompanamiento' => '2-Potencializar' })
  #
  # For a multiselect controller answer (an array), an overlap with the
  # configured trigger values counts as a match.
  def visible_for?(answers)
    return true if depends_on_jabvox.blank?

    triggers = Array(show_when_jabvox).map(&:to_s)
    return true if triggers.empty?

    given = answers.is_a?(Hash) ? answers[depends_on_jabvox] : nil
    Array(given).map(&:to_s).any? { |v| triggers.include?(v) }
  end

  # Coerces a raw user-supplied value into the storage form for this column's
  # type. Returns [coerced_value, error_message]. A blank value is always
  # allowed here (presence is enforced separately via required_jabvox), so the
  # caller decides how to treat nil. This is the single choke point that keeps
  # arbitrary/malformed data out of the JSONB payload.
  COERCERS = {
    'integer' => :coerce_integer,
    'float' => :coerce_float,
    'boolean' => :coerce_boolean,
    'date' => :coerce_date,
    'select' => :coerce_select,
    'multiselect' => :coerce_multiselect
  }.freeze

  def coerce(value)
    return [nil, nil] if value.nil? || value == ''

    method_name = COERCERS[column_type_jabvox]
    return [value.to_s, nil] unless method_name # text / unknown -> string

    send(method_name, value)
  end

  private

  def coerce_boolean(value)
    [ActiveModel::Type::Boolean.new.cast(value), nil]
  end

  def coerce_integer(value)
    Integer(value.to_s, 10)
    [value.to_s.to_i, nil]
  rescue ArgumentError, TypeError
    [nil, "#{label_jabvox}: must be an integer"]
  end

  def coerce_float(value)
    [Float(value), nil]
  rescue ArgumentError, TypeError
    [nil, "#{label_jabvox}: must be a number"]
  end

  def coerce_date(value)
    [Date.iso8601(value.to_s).iso8601, nil]
  rescue ArgumentError, TypeError
    [nil, "#{label_jabvox}: must be a valid date (YYYY-MM-DD)"]
  end

  def coerce_select(value)
    allowed = Array(options_jabvox).map(&:to_s)
    return [value.to_s, nil] if allowed.include?(value.to_s)

    [nil, "#{label_jabvox}: must be one of the configured options"]
  end

  # Stored as an array of strings, each validated against options_jabvox.
  # Accepts an array or a single value; drops blanks; rejects unknown options.
  def coerce_multiselect(value)
    allowed = Array(options_jabvox).map(&:to_s)
    values  = Array(value).map { |v| v.to_s.strip }.reject(&:empty?).uniq
    invalid = values - allowed
    return [nil, "#{label_jabvox}: must be from the configured options"] if invalid.any?

    [values, nil]
  end
end
