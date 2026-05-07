# == Schema Information
#
# Table name: jabvox_response_bot_roles
#
#  id            :bigint           not null, primary key
#  active_jabvox :boolean          default(TRUE), not null
#  name_jabvox   :string           not null
#  prompt_jabvox :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_jabvox_response_bot_roles_on_name_jabvox  (name_jabvox) UNIQUE
#
class JabvoxResponseBotRole < ApplicationRecord
  validates :name_jabvox, presence: true, uniqueness: true

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }

  has_many :jabvox_response_bot_configs, dependent: :nullify
end
