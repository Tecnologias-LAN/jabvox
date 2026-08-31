# frozen_string_literal: true

# Carpeta para organizar flujos dentro de una cuenta.
# == Schema Information
#
# Table name: jabvox_flow_folders
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_jabvox_flow_folders_account_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxFlowFolder < ApplicationRecord
  belongs_to :account
  has_many :flows, class_name: 'JabvoxFlow', foreign_key: :folder_id, dependent: :nullify, inverse_of: :folder

  validates :name, presence: true, uniqueness: { scope: :account_id }
end
