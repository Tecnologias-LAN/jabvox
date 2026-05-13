# == Schema Information
#
# Table name: jabvox_form_configs
#
#  id               :bigint           not null, primary key
#  base_url_jabvox  :string           default("")
#  max_forms_jabvox :integer          default(10), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_jabvox_form_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxFormConfig < ApplicationRecord
  self.table_name = 'jabvox_form_configs'

  belongs_to :account

  validates :max_forms_jabvox, numericality: { only_integer: true, greater_than: 0 }
end
