# == Schema Information
#
# Table name: jabvox_cdr_report_permissions
#
#  id         :bigint           not null, primary key
#  can_view   :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_cdr_report_permissions_on_account_id              (account_id)
#  index_jabvox_cdr_report_permissions_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#  index_jabvox_cdr_report_permissions_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxCdrReportPermission < ApplicationRecord
  self.table_name = 'jabvox_cdr_report_permissions'

  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
