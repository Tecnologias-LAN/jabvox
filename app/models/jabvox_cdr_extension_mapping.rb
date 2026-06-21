# == Schema Information
#
# Table name: jabvox_cdr_extension_mappings
#
#  id         :bigint           not null, primary key
#  extension  :string           not null
#  label      :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  idx_on_account_id_extension_8e86e57eba             (account_id,extension) UNIQUE
#  index_jabvox_cdr_extension_mappings_on_account_id  (account_id)
#  index_jabvox_cdr_extension_mappings_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxCdrExtensionMapping < ApplicationRecord
  self.table_name = 'jabvox_cdr_extension_mappings'

  belongs_to :account
  belongs_to :user, optional: true

  validates :extension, presence: true, uniqueness: { scope: :account_id }
end
