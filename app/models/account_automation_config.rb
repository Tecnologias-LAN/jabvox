# == Schema Information
#
# Table name: account_automation_configs
#
#  id                  :bigint           not null, primary key
#  enabled             :boolean          default(FALSE), not null
#  last_error          :text
#  last_provisioned_at :datetime
#  last_status         :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  remote_account_id   :bigint
#
# Indexes
#
#  index_account_automation_configs_on_account_id_unique  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class AccountAutomationConfig < ApplicationRecord
  self.table_name = 'account_automation_configs'

  belongs_to :account

  validates :account_id, uniqueness: true

  scope :enabled, -> { where(enabled: true) }
end
