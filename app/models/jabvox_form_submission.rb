# == Schema Information
#
# Table name: jabvox_form_submissions
#
#  id                :bigint           not null, primary key
#  data_jabvox       :jsonb
#  ip_address_jabvox :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  jabvox_form_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_form_submissions_on_account_id      (account_id)
#  index_jabvox_form_submissions_on_created_at      (created_at)
#  index_jabvox_form_submissions_on_jabvox_form_id  (jabvox_form_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_form_id => jabvox_forms.id)
#
class JabvoxFormSubmission < ApplicationRecord
  self.table_name = 'jabvox_form_submissions'

  belongs_to :jabvox_form
  belongs_to :account

  validates :data_jabvox, presence: true
end
