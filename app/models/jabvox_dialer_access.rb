# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_dialer_accesses
#
#  id         :bigint           not null, primary key
#  can_access :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_dialer_accesses_account_user   (account_id,user_id) UNIQUE
#  index_jabvox_dialer_accesses_on_account_id  (account_id)
#
class JabvoxDialerAccess < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
