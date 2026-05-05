# == Schema Information
#
# Table name: jabvox_sales_report_accesses
#
#  id                      :bigint           not null, primary key
#  can_view_reports_jabvox :boolean          default(FALSE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  user_id                 :bigint           not null
#
# Indexes
#
#  index_jabvox_report_access_account_user           (account_id,user_id) UNIQUE
#  index_jabvox_sales_report_accesses_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxSalesReportAccess < ApplicationRecord
  self.table_name = 'jabvox_sales_report_accesses'

  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
