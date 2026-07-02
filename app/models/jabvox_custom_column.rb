# == Schema Information
#
# Table name: jabvox_custom_columns
#
#  id                     :bigint           not null, primary key
#  column_type_jabvox     :string           default("text"), not null
#  label_jabvox           :string           not null
#  name_jabvox            :string           not null
#  options_jabvox         :jsonb
#  position_jabvox        :integer          default(0), not null
#  required_jabvox        :boolean          default(FALSE), not null
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
  COLUMN_TYPES = %w[text integer float boolean date select].freeze

  belongs_to :jabvox_custom_table

  validates :name_jabvox, presence: true, uniqueness: { scope: :jabvox_custom_table_id }
  validates :label_jabvox, presence: true
  validates :column_type_jabvox, inclusion: { in: COLUMN_TYPES }

  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }

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
    'select' => :coerce_select
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
end
