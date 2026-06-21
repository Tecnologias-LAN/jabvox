# == Schema Information
#
# Table name: jabvox_whatsapp_template_permissions
#
#  id         :bigint           not null, primary key
#  can_manage :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  idx_jabvox_wa_template_perms_account_user                 (account_id,user_id) UNIQUE
#  index_jabvox_whatsapp_template_permissions_on_account_id  (account_id)
#  index_jabvox_whatsapp_template_permissions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxWhatsappTemplatePermission < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_template_permissions'

  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
