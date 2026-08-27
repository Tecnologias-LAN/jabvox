# frozen_string_literal: true

# Ajustes del softphone tras unificar con VoIP:
#   - La EXTENSIÓN sale de jabvox_user_extensions (VoIP). jabvox_softphone_extensions pasa a
#     guardar SOLO la credencial SIP (secreto) del usuario para WebRTC, ligada por
#     user+account. Se quitan extension y sip_username (ya no se duplican).
#   - Nueva tabla jabvox_softphone_call_logs: historial del softphone (número, dirección,
#     duración, cuándo, estado), para la pestaña de historial dentro del teléfono.
class RefactorSoftphoneExtensionAndCallLogs < ActiveRecord::Migration[7.1]
  def change
    # La extensión ya no vive aquí (viene de VoIP); el índice único por extensión sobra.
    remove_index :jabvox_softphone_extensions, column: [:account_id, :extension], if_exists: true
    remove_column :jabvox_softphone_extensions, :extension, :string, if_exists: true
    remove_column :jabvox_softphone_extensions, :sip_username, :string, if_exists: true

    create_table :jabvox_softphone_call_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :extension, null: false            # con qué extensión se hizo la llamada
      t.string :phone_number, null: false         # a quién / de quién
      t.string :contact_name                      # nombre resuelto (si se conoce)
      t.integer :direction, null: false, default: 0 # 0=outbound, 1=inbound
      t.integer :status, null: false, default: 0    # ringing/answered/missed/failed/ended
      t.datetime :started_at
      t.datetime :answered_at
      t.datetime :ended_at
      t.integer :duration_seconds, null: false, default: 0
      t.string :call_uuid                         # id de la sesión SIP
      t.timestamps
    end
    add_index :jabvox_softphone_call_logs, [:account_id, :user_id, :created_at]
    add_index :jabvox_softphone_call_logs, :call_uuid
  end
end
