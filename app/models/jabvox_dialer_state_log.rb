# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_dialer_state_logs
#
#  id           :bigint           not null, primary key
#  dialer_state :string           default("inactive"), not null
#  ended_at     :datetime
#  started_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  idx_on_account_id_user_id_started_at_ee4c1f49a2         (account_id,user_id,started_at)
#  index_jabvox_dialer_state_logs_on_account_id            (account_id)
#  index_jabvox_dialer_state_logs_on_user_id_and_ended_at  (user_id,ended_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxDialerStateLog < ApplicationRecord
  belongs_to :account
  belongs_to :user
end
