class MoveResponseEmailToBulkWhatsappBatches < ActiveRecord::Migration[7.1]
  def change
    # The report email is now chosen per send (on the send screen), not in account settings.
    add_column :jabvox_bulk_whatsapp_batches, :response_email_jabvox, :string, default: '', null: false
  end
end
