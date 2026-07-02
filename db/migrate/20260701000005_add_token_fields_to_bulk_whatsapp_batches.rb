class AddTokenFieldsToBulkWhatsappBatches < ActiveRecord::Migration[7.1]
  def change
    # The ephemeral access token minted for this batch and when it expires, so we can audit it
    # and revoke it. The token value itself is never stored (only its DB id) to limit exposure.
    add_column :jabvox_bulk_whatsapp_batches, :access_token_id_jabvox, :bigint
    add_column :jabvox_bulk_whatsapp_batches, :token_expires_at_jabvox, :datetime
  end
end
