# == Schema Information
#
# Table name: jabvox_user_extensions
#
#  id               :bigint           not null, primary key
#  extension_jabvox :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  idx_user_extensions_on_account_ext          (account_id,extension_jabvox) UNIQUE
#  idx_user_extensions_on_account_user         (account_id,user_id) UNIQUE
#  index_jabvox_user_extensions_on_account_id  (account_id)
#  index_jabvox_user_extensions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxUserExtension < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :extension_jabvox, presence: true,
                               format: { with: /\A\d{1,10}\z/ },
                               uniqueness: { scope: :account_id }
  validates :user_id, uniqueness: { scope: :account_id }
end
