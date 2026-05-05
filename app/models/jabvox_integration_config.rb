# == Schema Information
#
# Table name: jabvox_integration_configs
#
#  id                       :bigint           not null, primary key
#  company_address_jabvox   :text
#  company_email_jabvox     :string
#  company_logo_jabvox      :text
#  company_name_jabvox      :string
#  company_nit_jabvox       :string
#  company_phone_jabvox     :string
#  company_website_jabvox   :string
#  integration_email_jabvox :text
#  integration_token_jabvox :text
#  integration_type_jabvox  :string           default("alegra")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_jabvox_integration_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxIntegrationConfig < ApplicationRecord
  self.table_name = 'jabvox_integration_configs'

  INTEGRATION_TYPES = %w[alegra zoho_books xero quickbooks odoo].freeze

  belongs_to :account

  validates :integration_type_jabvox, inclusion: { in: INTEGRATION_TYPES }, allow_nil: true
  validates :company_logo_jabvox, length: { maximum: 3_000_000 }, allow_blank: true
end
