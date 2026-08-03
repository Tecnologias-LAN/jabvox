# Turns the bulk WhatsApp module into per-execution reports:
#   - Extends batches with reporting fields (uuid, callback token, source, template
#     snapshot, filters, counts, reuse link, finished_at). All ADDITIVE — the
#     existing n8n contract (payload_jabvox, response_email_jabvox) is untouched.
#   - Adds a recipients table: one row per destinatario/resultado, so each batch
#     has its own detailed report (who, status, Meta error, message id).
class AddBulkWhatsappRecipientsAndBatchReporting < ActiveRecord::Migration[7.0]
  # Idempotente: la VM arranca de un dump de producción, así que cada columna,
  # tabla e índice se crea solo si falta. Re-correrla nunca falla.
  BATCH_COLUMNS = {
    batch_uuid_jabvox: { type: :uuid },
    callback_token_jabvox: { type: :string },
    source_type_jabvox: { type: :string },
    template_name_jabvox: { type: :string },
    template_language_jabvox: { type: :string },
    template_category_jabvox: { type: :string },
    variable_mapping_jabvox: { type: :jsonb, default: {}, null: false },
    filters_jabvox: { type: :jsonb, default: {}, null: false },
    sent_count_jabvox: { type: :integer, default: 0, null: false },
    failed_count_jabvox: { type: :integer, default: 0, null: false },
    source_batch_id_jabvox: { type: :bigint },
    finished_at_jabvox: { type: :datetime }
  }.freeze

  def up
    BATCH_COLUMNS.each do |name, opts|
      next if column_exists?(:jabvox_bulk_whatsapp_batches, name)

      add_column :jabvox_bulk_whatsapp_batches, name, opts[:type], **opts.except(:type)
    end

    add_index :jabvox_bulk_whatsapp_batches, :batch_uuid_jabvox, unique: true,
                                                                 name: 'idx_bulk_wa_batches_uuid', if_not_exists: true
    add_index :jabvox_bulk_whatsapp_batches, :source_batch_id_jabvox,
              name: 'idx_bulk_wa_batches_source_batch', if_not_exists: true

    create_recipients_table
  end

  def down
    drop_table :jabvox_bulk_whatsapp_recipients, if_exists: true
    BATCH_COLUMNS.each_key do |name|
      remove_column :jabvox_bulk_whatsapp_batches, name if column_exists?(:jabvox_bulk_whatsapp_batches, name)
    end
  end

  private

  def create_recipients_table
    return if table_exists?(:jabvox_bulk_whatsapp_recipients)

    create_table :jabvox_bulk_whatsapp_recipients do |t|
      t.bigint :bulk_whatsapp_batch_id, null: false
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.string :lead_id_jabvox
      t.string :name_jabvox, default: '', null: false
      t.string :phone_number_jabvox, default: '', null: false
      t.string :email_jabvox
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.jsonb :processed_params_jabvox, default: {}, null: false
      t.text :rendered_content_jabvox
      t.string :status_jabvox, default: 'pending', null: false
      t.bigint :conversation_id
      t.bigint :chatwoot_message_id
      t.string :error_code_jabvox
      t.text :error_message_jabvox
      t.datetime :sent_at_jabvox
      t.timestamps
      t.index :bulk_whatsapp_batch_id, name: 'idx_bulk_wa_recipients_batch'
      t.index :status_jabvox, name: 'idx_bulk_wa_recipients_status'
      t.index %i[bulk_whatsapp_batch_id status_jabvox], name: 'idx_bulk_wa_recipients_batch_status'
      t.index :chatwoot_message_id, name: 'idx_bulk_wa_recipients_message'
    end
  end
end
