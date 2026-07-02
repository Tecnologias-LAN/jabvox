# Per-account configuration for the Bulk WhatsApp module: the n8n webhook URL that receives
# the parsed CSV plus the account/inbox identity so it can create contacts/conversations and
# send templates back through the Jabvox API.
# == Schema Information
#
# Table name: jabvox_bulk_whatsapp_configs
#
#  id                    :bigint           not null, primary key
#  response_email_jabvox :string           default(""), not null
#  webhook_url_jabvox    :text             default(""), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#
# Indexes
#
#  index_jabvox_bulk_whatsapp_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxBulkWhatsappConfig < ApplicationRecord
  self.table_name = 'jabvox_bulk_whatsapp_configs'

  belongs_to :account

  validates :account_id, uniqueness: true
  validates :webhook_url_jabvox,
            format: { with: %r{\Ahttps?://}i, message: 'debe ser una URL http(s) válida' },
            allow_blank: true

  # A bulk send only needs the webhook configured here; the report email is chosen per send.
  def ready?
    webhook_url_jabvox.present?
  end
end
