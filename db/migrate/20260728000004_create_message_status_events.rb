# Captures WhatsApp (Meta) delivery-status transitions per message with their
# real timestamps, which Chatwoot does not persist today (the webhook handler
# only overwrites messages.status, losing WHEN each transition happened).
#
# One row per (message, status) transition. Additive and independent of the
# messages table — powers the WhatsApp agent report's time-to-delivered /
# time-to-read metrics. error_code/error_title keep Meta's failure detail split
# out (today only a joined string lives in content_attributes.external_error).
class CreateMessageStatusEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :message_status_events do |t|
      t.bigint :message_id, null: false
      t.bigint :account_id, null: false
      t.bigint :conversation_id
      t.bigint :inbox_id
      t.integer :status, null: false # mirrors messages enum: sent0 delivered1 read2 failed3
      t.datetime :occurred_at, null: false
      t.string :error_code
      t.string :error_title
      t.datetime :created_at, null: false
    end

    # One row per (message,status): a repeated webhook for the same transition
    # is a no-op instead of a duplicate.
    add_index :message_status_events, %i[message_id status], unique: true,
                                                             name: 'idx_message_status_events_unique'
    add_index :message_status_events, %i[account_id occurred_at],
              name: 'idx_message_status_events_account_time'
    add_index :message_status_events, :inbox_id, name: 'idx_message_status_events_inbox'
  end
end
