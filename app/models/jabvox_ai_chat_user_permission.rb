# == Schema Information
#
# Table name: jabvox_ai_chat_user_permissions
#
#  id                       :bigint           not null, primary key
#  can_use_documents_jabvox :boolean          default(TRUE), not null
#  can_use_jabvox           :boolean          default(TRUE), not null
#  can_use_models_jabvox    :boolean          default(TRUE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  user_id                  :bigint           not null
#
# Indexes
#
#  idx_jabvox_ai_chat_permissions_unique  (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAiChatUserPermission < ApplicationRecord
  belongs_to :account
  belongs_to :user

  def self.for(account_id, user_id)
    find_or_initialize_by(account_id: account_id, user_id: user_id)
  end
end
