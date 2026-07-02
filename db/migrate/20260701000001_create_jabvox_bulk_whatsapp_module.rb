class CreateJabvoxBulkWhatsappModule < ActiveRecord::Migration[7.1]
  def change
    # Super-admin toggle for the Bulk WhatsApp (mass template send) module.
    add_column :accounts, :jabvox_bulk_whatsapp_enabled_jabvox, :boolean, default: false, null: false

    create_config
    create_batches
  end

  private

  # Per-account config: the n8n webhook URL the parsed CSV is POSTed to.
  def create_config
    create_table :jabvox_bulk_whatsapp_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.text :webhook_url_jabvox, default: '', null: false
      t.timestamps
    end
  end

  # One row per bulk send, for the audit/history view.
  def create_batches
    create_table :jabvox_bulk_whatsapp_batches do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, foreign_key: true, null: true
      # The user whose API token is forwarded to n8n so it can act on their behalf.
      t.references :sender_user, foreign_key: { to_table: :users }, null: true
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.integer :total_rows_jabvox, default: 0, null: false
      t.integer :valid_rows_jabvox, default: 0, null: false
      t.string :status_jabvox, default: 'pending', null: false # pending | sent | failed
      t.text :error_jabvox
      t.string :file_name_jabvox, default: '', null: false
      t.datetime :sent_at_jabvox
      t.timestamps

      t.index [:account_id, :created_at]
    end
  end
end
