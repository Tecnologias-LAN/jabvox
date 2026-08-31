# frozen_string_literal: true

# Variable GLOBAL de cuenta: `{{global.<key>}}`. Persistente, a diferencia de las
# de ejecución `{{vars.x}}`.
# == Schema Information
#
# Table name: jabvox_flow_account_variables
#
#  id          :bigint           not null, primary key
#  description :string
#  key         :string           not null
#  secret      :boolean          default(FALSE), not null
#  value       :text             default(""), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  idx_jabvox_flow_vars_account_key  (account_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxFlowAccountVariable < ApplicationRecord
  belongs_to :account

  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,48}\z/

  validates :key, presence: true, uniqueness: { scope: :account_id }, format: { with: KEY_FORMAT }
end
