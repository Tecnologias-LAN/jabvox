# Turns the bulk WhatsApp module into per-execution reports:
#   - Extends batches with reporting fields (uuid, callback token, source, template
#     snapshot, filters, counts, reuse link, finished_at). All ADDITIVE — the
#     existing n8n contract (payload_jabvox, response_email_jabvox) is untouched.
#   - Adds a recipients table: one row per destinatario/resultado, so each batch
#     has its own detailed report (who, status, Meta error, message id).
class AddBulkWhatsappRecipientsAndBatchReporting < ActiveRecord::Migration[7.0]
  def change
    change_table :jabvox_bulk_whatsapp_batches, bulk: true do |t|
      t.uuid :batch_uuid_jabvox
      t.string :callback_token_jabvox
      t.string :source_type_jabvox # 'csv' | 'jabvox'
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.string :template_category_jabvox
      t.jsonb :variable_mapping_jabvox, default: {}, null: false
      t.jsonb :filters_jabvox, default: {}, null: false
      t.integer :sent_count_jabvox, default: 0, null: false
      t.integer :failed_count_jabvox, default: 0, null: false
      t.bigint :source_batch_id_jabvox
      t.datetime :finished_at_jabvox
    end

    add_index :jabvox_bulk_whatsapp_batches, :batch_uuid_jabvox, unique: true,
                                                                 name: 'idx_bulk_wa_batches_uuid'
    add_index :jabvox_bulk_whatsapp_batches, :source_batch_id_jabvox,
              name: 'idx_bulk_wa_batches_source_batch'

    create_table :jabvox_bulk_whatsapp_recipients do |t|
      t.bigint :bulk_whatsapp_batch_id, null: false
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.string :lead_id_jabvox # lead id de origen (string: permite ids externos/nulos)
      t.string :name_jabvox, default: '', null: false
      t.string :phone_number_jabvox, default: '', null: false
      t.string :email_jabvox
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.jsonb :processed_params_jabvox, default: {}, null: false
      t.text :rendered_content_jabvox
      t.string :status_jabvox, default: 'pending', null: false # pending|sent|failed
      t.bigint :conversation_id
      t.bigint :chatwoot_message_id
      t.string :error_code_jabvox
      t.text :error_message_jabvox
      t.datetime :sent_at_jabvox
      t.timestamps
    end

    add_index :jabvox_bulk_whatsapp_recipients, :bulk_whatsapp_batch_id,
              name: 'idx_bulk_wa_recipients_batch'
    add_index :jabvox_bulk_whatsapp_recipients, :status_jabvox,
              name: 'idx_bulk_wa_recipients_status'
    add_index :jabvox_bulk_whatsapp_recipients, %i[bulk_whatsapp_batch_id status_jabvox],
              name: 'idx_bulk_wa_recipients_batch_status'
    add_index :jabvox_bulk_whatsapp_recipients, :chatwoot_message_id,
              name: 'idx_bulk_wa_recipients_message'
  end
end
