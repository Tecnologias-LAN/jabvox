class AddModeToBulkWhatsappBatches < ActiveRecord::Migration[7.1]
  def change
    # 'template' (official WhatsApp) or 'text' (Evolution / API), derived from the inbox at
    # send time. Stored so the history shows how each batch was sent.
    add_column :jabvox_bulk_whatsapp_batches, :mode_jabvox, :string, default: 'template', null: false
  end
end
