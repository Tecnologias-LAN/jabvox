# One row per outbound email sent through Jabvox SMTP (see EmailSenderService).
# Feeds the analytics Email report (count by status / source / agent / day).
# == Schema Information
#
# Table name: jabvox_email_send_logs
#
#  id            :bigint           not null, primary key
#  error_message :text
#  sent_at       :datetime
#  source        :string           default("manual"), not null
#  status        :string           default("sent"), not null
#  subject       :string           default(""), not null
#  to_email      :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  user_id       :bigint
#
# Indexes
#
#  index_jabvox_email_send_logs_on_account_id                 (account_id)
#  index_jabvox_email_send_logs_on_account_id_and_created_at  (account_id,created_at)
#  index_jabvox_email_send_logs_on_account_id_and_status      (account_id,status)
#  index_jabvox_email_send_logs_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxEmailSendLog < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  STATUSES = %w[sent failed].freeze
  SOURCES = %w[manual kanban task calendar form system].freeze

  validates :to_email, presence: true
  validates :status, inclusion: { in: STATUSES }
end
