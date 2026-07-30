# One row per destinatario of a bulk WhatsApp send, with its own result: whether
# the template was delivered, the Meta error if it failed, and the ids needed to
# reconcile status later (chatwoot_message_id / conversation_id). This is what the
# per-execution report renders and what "reenviar a esta audiencia" clones.
# == Schema Information
#
# Table name: jabvox_bulk_whatsapp_recipients
#
#  id                       :bigint           not null, primary key
#  email_jabvox             :string
#  error_code_jabvox        :string
#  error_message_jabvox     :text
#  lead_id_jabvox           :string
#  name_jabvox              :string           default(""), not null
#  phone_number_jabvox      :string           default(""), not null
#  processed_params_jabvox  :jsonb            not null
#  rendered_content_jabvox  :text
#  sent_at_jabvox           :datetime
#  status_jabvox            :string           default("pending"), not null
#  template_language_jabvox :string
#  template_name_jabvox     :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  bulk_whatsapp_batch_id   :bigint           not null
#  chatwoot_message_id      :bigint
#  contact_id               :bigint
#  conversation_id          :bigint
#
# Indexes
#
#  idx_bulk_wa_recipients_batch         (bulk_whatsapp_batch_id)
#  idx_bulk_wa_recipients_batch_status  (bulk_whatsapp_batch_id,status_jabvox)
#  idx_bulk_wa_recipients_message       (chatwoot_message_id)
#  idx_bulk_wa_recipients_status        (status_jabvox)
#
class JabvoxBulkWhatsappRecipient < ApplicationRecord
  self.table_name = 'jabvox_bulk_whatsapp_recipients'

  STATUSES = %w[pending sent failed].freeze

  belongs_to :batch, class_name: 'JabvoxBulkWhatsappBatch',
                     foreign_key: :bulk_whatsapp_batch_id, inverse_of: :recipients
  belongs_to :account

  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :phone_number_jabvox, presence: true

  scope :sent,    -> { where(status_jabvox: 'sent') }
  scope :failed,  -> { where(status_jabvox: 'failed') }
  scope :pending, -> { where(status_jabvox: 'pending') }
end
