# Audit record of one bulk WhatsApp send: which inbox, whose API token was forwarded, how many
# rows the CSV had, and whether the POST to the n8n webhook succeeded. Shown in the module's
# history view.
# == Schema Information
#
# Table name: jabvox_bulk_whatsapp_batches
#
#  id                      :bigint           not null, primary key
#  access_token_id_jabvox  :bigint
#  attempts_jabvox         :integer          default(0), not null
#  error_jabvox            :text
#  file_name_jabvox        :string           default(""), not null
#  mode_jabvox             :string           default("template"), not null
#  payload_jabvox          :jsonb            not null
#  response_email_jabvox   :string           default(""), not null
#  sent_at_jabvox          :datetime
#  status_jabvox           :string           default("pending"), not null
#  token_expires_at_jabvox :datetime
#  total_rows_jabvox       :integer          default(0), not null
#  valid_rows_jabvox       :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  created_by_id           :bigint
#  inbox_id                :bigint
#  sender_user_id          :bigint
#
# Indexes
#
#  idx_on_account_id_created_at_793a6e41e6               (account_id,created_at)
#  idx_on_account_id_status_jabvox_8e3a4a349f            (account_id,status_jabvox)
#  index_jabvox_bulk_whatsapp_batches_on_account_id      (account_id)
#  index_jabvox_bulk_whatsapp_batches_on_created_by_id   (created_by_id)
#  index_jabvox_bulk_whatsapp_batches_on_inbox_id        (inbox_id)
#  index_jabvox_bulk_whatsapp_batches_on_sender_user_id  (sender_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sender_user_id => users.id)
#
class JabvoxBulkWhatsappBatch < ApplicationRecord
  self.table_name = 'jabvox_bulk_whatsapp_batches'

  STATUSES = %w[pending sent failed].freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :sender_user, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  validates :status_jabvox, inclusion: { in: STATUSES }
end
