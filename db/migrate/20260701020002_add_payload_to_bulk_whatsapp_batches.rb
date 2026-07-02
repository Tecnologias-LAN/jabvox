class AddPayloadToBulkWhatsappBatches < ActiveRecord::Migration[7.1]
  def change
    # Snapshot of what to send, resolved when the batch is queued. For CSV it holds the parsed
    # rows; for leads it holds the selection + message spec that the background job expands.
    # Kept as jsonb so the delivery job can run detached from the original request/upload.
    add_column :jabvox_bulk_whatsapp_batches, :payload_jabvox, :jsonb, default: {}, null: false
    add_column :jabvox_bulk_whatsapp_batches, :attempts_jabvox, :integer, default: 0, null: false
    add_index :jabvox_bulk_whatsapp_batches, [:account_id, :status_jabvox]
  end
end
