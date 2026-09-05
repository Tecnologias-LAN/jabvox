# frozen_string_literal: true

# Registro por LLAMADA individual del Voice Broadcast: una fila por cada intento de
# marcación a un destinatario (no se sobrescribe como en recipients). Permite un
# reporte histórico completo — cada llamada con su desenlace, AMD, DTMF, duración,
# grabación y tiempos — aunque el destinatario se reintente varias veces.
class CreateJabvoxVoiceBroadcastCallLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_voice_broadcast_call_logs do |t|
      t.references :jabvox_voice_broadcast, null: false, index: { name: 'idx_vb_call_logs_broadcast' }
      t.bigint :jabvox_voice_broadcast_recipient_id, null: false
      t.bigint :account_id, null: false
      t.bigint :contact_id
      t.string  :phone_jabvox, null: false
      t.string  :name_jabvox
      t.integer :attempt_number_jabvox, null: false, default: 1 # nº de intento (1,2,3…)
      t.string  :outcome_jabvox        # answered_human / no_answer / busy / ...
      t.string  :amd_status_jabvox     # HUMAN / MACHINE / NOTSURE
      t.string  :dtmf_pressed_jabvox
      t.boolean :played_full_jabvox, null: false, default: false
      t.integer :duration_ms_jabvox
      t.string  :recording_file_jabvox
      t.string  :uniqueid_jabvox
      t.string  :linkedid_jabvox
      t.string  :hangup_cause_jabvox   # causa Q.850 del hangup (16, 17, 34…)
      t.datetime :started_at_jabvox    # cuándo se originó esta llamada
      t.datetime :ended_at_jabvox      # cuándo terminó (hangup/desenlace)
      t.timestamps
    end

    add_index :jabvox_voice_broadcast_call_logs, :jabvox_voice_broadcast_recipient_id, name: 'idx_vb_call_logs_recipient'
    add_index :jabvox_voice_broadcast_call_logs, [:account_id, :created_at], name: 'idx_vb_call_logs_account_created'
    add_index :jabvox_voice_broadcast_call_logs, :uniqueid_jabvox, name: 'idx_vb_call_logs_uniqueid'
  end
end
