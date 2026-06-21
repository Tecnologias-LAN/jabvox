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
end
