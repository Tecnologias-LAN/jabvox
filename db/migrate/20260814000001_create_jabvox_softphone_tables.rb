# frozen_string_literal: true

# Softphone WebRTC "Jabvox": marcador en el navegador (SIP.js sobre WSS + DTLS-SRTP).
# Es un módulo NUEVO e independiente del dialer AMI existente.
#
#   - accounts.jabvox_softphone_enabled_jabvox: activa el módulo por cuenta (super admin).
#   - jabvox_softphone_configs: configuración WebRTC por cuenta (WSS, codecs, TURN, etc.).
#   - jabvox_softphone_extensions: liga una extensión a un usuario con su credencial SIP
#     (secreto CIFRADO en BD). Se apoya en jabvox_user_extensions (usuario↔ext ya existe).
class CreateJabvoxSoftphoneTables < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_softphone_enabled_jabvox, :boolean, null: false, default: false

    create_table :jabvox_softphone_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :wss_url                         # wss://pbx.dominio:8089/ws
      t.string :sip_domain                      # dominio SIP del PBX
      t.jsonb :codecs, null: false, default: %w[opus alaw ulaw]
      t.boolean :auto_answer, null: false, default: false
      t.string :dtmf_mode, null: false, default: 'rfc2833' # rfc2833 | info | inband
      t.boolean :transfer_enabled, null: false, default: true
      t.string :default_context, null: false, default: 'from-webrtc'
      # TURN/STUN. El secret de TURN se cifra (credenciales temporales HMAC).
      t.jsonb :stun_servers, null: false, default: []
      t.string :turn_url
      t.text :turn_secret                       # cifrado; se usa para generar credenciales temporales
      t.integer :credential_ttl, null: false, default: 3600 # segundos de vida de la credencial efímera
      t.timestamps
    end

    create_table :jabvox_softphone_extensions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :extension, null: false          # p.ej. "1001"
      t.string :sip_username, null: false       # usuario SIP para registrar (PJSIP endpoint)
      t.text :sip_secret                        # CIFRADO; nunca se expone tal cual al cliente
      t.boolean :webrtc_enabled, null: false, default: true
      t.timestamps
    end
    add_index :jabvox_softphone_extensions, [:account_id, :extension], unique: true
    add_index :jabvox_softphone_extensions, [:account_id, :user_id], unique: true
  end
end
