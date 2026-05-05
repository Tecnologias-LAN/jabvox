# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_app_state_logs
#
#  id           :bigint           not null, primary key
#  ended_at     :datetime
#  started_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  app_state_id :integer
#  user_id      :bigint           not null
#
# Indexes
#
#  idx_on_account_id_user_id_started_at_a0274f796f      (account_id,user_id,started_at)
#  index_jabvox_app_state_logs_on_account_id            (account_id)
#  index_jabvox_app_state_logs_on_user_id_and_ended_at  (user_id,ended_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAppStateLog < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :jabvox_app_state, optional: true, foreign_key: :app_state_id
end
