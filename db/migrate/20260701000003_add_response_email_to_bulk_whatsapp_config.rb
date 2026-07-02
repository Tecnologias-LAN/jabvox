class AddResponseEmailToBulkWhatsappConfig < ActiveRecord::Migration[7.1]
  def change
    # Email address n8n reports the send result to. Required (together with the webhook URL)
    # before a bulk send is allowed.
    add_column :jabvox_bulk_whatsapp_configs, :response_email_jabvox, :string, default: '', null: false
  end
end
