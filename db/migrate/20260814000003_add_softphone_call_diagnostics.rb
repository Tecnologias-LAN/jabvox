# frozen_string_literal: true

# Diagnóstico detallado de las llamadas del softphone:
#   - En call_logs: codec negociado, motivo de fallo, código de fallo y contexto de entrada.
#   - Nueva tabla de EVENTOS por llamada (registrar/invite/answer/dtmf/hangup/error) con
#     timestamp, para reconstruir qué pasó en cada llamada desde el panel.
class AddSoftphoneCallDiagnostics < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_softphone_call_logs, bulk: true do |t|
      t.string :codec               # codec de audio negociado (opus/alaw/...)
      t.string :failure_reason      # texto legible del fallo
      t.string :failure_code        # código corto (sip 4xx/5xx, ice_failed, etc.)
      t.string :sip_context         # contexto de Asterisk por el que entró/salió
      t.string :remote_ip           # IP remota (diagnóstico), sin datos sensibles
    end

    create_table :jabvox_softphone_call_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_softphone_call_log, null: false, foreign_key: true,
                                               index: { name: 'idx_sp_events_on_call_log' }
      t.string :event_type, null: false   # registered|invite|answer|dtmf|hold|transfer|hangup|error
      t.string :detail                    # dato corto del evento (dígito DTMF, motivo, etc.)
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :jabvox_softphone_call_events, [:account_id, :occurred_at]
  end
end
