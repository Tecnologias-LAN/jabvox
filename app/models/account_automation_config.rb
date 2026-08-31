# == Schema Information
#
# Table name: account_automation_configs
#
#  id                         :bigint           not null, primary key
#  api_key_jabvox             :text
#  api_key_prefix_jabvox      :string
#  api_key_set_at_jabvox      :datetime
#  automations_state          :integer          default(0), not null
#  automations_user_set_at    :datetime
#  automations_user_set_ip    :string
#  enabled                    :boolean          default(FALSE), not null
#  last_error                 :text
#  last_provisioned_at        :datetime
#  last_status                :string
#  max_flows                  :integer
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  automations_user_id        :bigint
#  automations_user_set_by_id :bigint
#  remote_account_id          :bigint
#
# Indexes
#
#  index_account_automation_configs_on_account_id_unique    (account_id) UNIQUE
#  index_account_automation_configs_on_automations_user_id  (automations_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (automations_user_id => users.id) ON DELETE => nullify
#
# Configuración por cuenta del módulo de Automatizaciones Avanzadas (flujos).
# Tras internalizar el motor en Ruby solo quedan `enabled` y `max_flows`; las
# columnas de la antigua app externa siguen en la tabla pero ya no se leen.
class AccountAutomationConfig < ApplicationRecord
  self.table_name = 'account_automation_configs'

  belongs_to :account

  validates :account_id, uniqueness: true
  # max_flows nil = ilimitado; si viene, debe ser positivo.
  validates :max_flows, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :enabled, -> { where(enabled: true) }
end
