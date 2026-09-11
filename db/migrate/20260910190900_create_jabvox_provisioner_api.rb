# frozen_string_literal: true

# API Provisioner (Hermes → Jabvox): superficie administrativa altamente privilegiada,
# separada del sistema Hermes por-cuenta. Tres tablas:
#
#   jabvox_provisioner_api_tokens  — el token ÚNICO (máx 1 activo, garantizado por índice
#                                    único parcial). Se guarda SOLO el hash, nunca el token.
#   jabvox_provisioner_sessions    — la ÚNICA conexión/cliente autorizado (fingerprint/IP/
#                                    heartbeat) + los nonces vistos (anti-replay).
#   jabvox_provisioner_audit_logs  — auditoría de cada petición (con secretos saneados).
#
# La allowlist de IP y el checklist de permisos (ver/editar/crear por recurso) viven en el
# propio token (jsonb), para que cada request los consulte FRESCOS (sin caché).
class CreateJabvoxProvisionerApi < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_provisioner_api_tokens do |t|
      # Solo el hash SHA-256 del token (hex, 64 chars). El token original jamás se guarda.
      t.string  :token_hash_jabvox, null: false
      # Secreto de FIRMA independiente del token (cifrado en reposo). Se usa como clave HMAC
      # para firmar cada request, de modo que capturar el header Bearer no baste para forjar
      # firmas. Se entrega UNA sola vez junto al token al generarlo.
      t.text    :signing_secret_jabvox
      # Prefijo público corto para identificar el token en la UI/auditoría sin revelarlo.
      t.string  :token_prefix_jabvox, null: false
      t.string  :status_jabvox, null: false, default: 'active' # active | revoked
      # Allowlist de IPs permitidas (array de strings). Vacío = ninguna (bloquea todo).
      t.jsonb   :allowed_ips_jabvox, null: false, default: []
      # Checklist de permisos: { "accounts" => ["view","edit","create"], ... } (nunca delete).
      t.jsonb   :permissions_jabvox, null: false, default: {}
      t.string  :label_jabvox
      t.bigint  :created_by_id # SuperAdmin/User que lo generó
      t.datetime :last_used_at_jabvox
      t.datetime :revoked_at_jabvox
      t.timestamps
    end
    # HASH único global.
    add_index :jabvox_provisioner_api_tokens, :token_hash_jabvox, unique: true,
                                                                  name: 'idx_provisioner_token_hash'
    # MÁXIMO 1 TOKEN ACTIVO en toda la app (garantía a nivel BD; imposible tener 2).
    add_index :jabvox_provisioner_api_tokens, :status_jabvox, unique: true,
                                                              where: "status_jabvox = 'active'", name: 'idx_one_active_provisioner_token'

    create_table :jabvox_provisioner_sessions do |t|
      t.references :provisioner_api_token, null: false,
                                           foreign_key: { to_table: :jabvox_provisioner_api_tokens }
      # Identidad única del cliente (PROVISIONER_CLIENT): una sola conexión autorizada.
      t.string   :client_id_jabvox, null: false
      t.string   :bound_ip_jabvox, null: false          # IP fijada en el primer handshake
      t.string   :fingerprint_jabvox                     # fingerprint de conexión (opcional)
      t.string   :status_jabvox, null: false, default: 'active' # active | closed
      t.datetime :last_heartbeat_at_jabvox
      t.timestamps
    end
    # UNA sola sesión activa por token.
    add_index :jabvox_provisioner_sessions, :status_jabvox, unique: true,
                                                            where: "status_jabvox = 'active'", name: 'idx_one_active_provisioner_session'

    # Anti-replay: nonces ya vistos (con su timestamp para poder purgar los caducados).
    create_table :jabvox_provisioner_nonces do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string   :nonce_jabvox, null: false
      t.datetime :seen_at_jabvox, null: false
    end
    add_index :jabvox_provisioner_nonces, :nonce_jabvox, unique: true,
                                                         name: 'idx_provisioner_nonce'
    add_index :jabvox_provisioner_nonces, :seen_at_jabvox, name: 'idx_provisioner_nonce_seen'

    create_table :jabvox_provisioner_audit_logs do |t|
      t.bigint   :provisioner_api_token_id
      t.string   :resource_jabvox                         # accounts, users, plans...
      t.string   :action_jabvox                           # view | edit | create
      t.string   :outcome_jabvox, null: false             # ok | denied | error
      t.string   :reason_jabvox                            # código de rechazo si denied
      t.string   :ip_jabvox
      t.integer  :account_context_id                       # cuenta afectada, si aplica
      t.jsonb    :params_jabvox, null: false, default: {}  # SANEADOS (sin secretos)
      t.integer  :http_status_jabvox
      t.datetime :created_at, null: false
    end
    add_index :jabvox_provisioner_audit_logs, :created_at, name: 'idx_provisioner_audit_created'
    add_index :jabvox_provisioner_audit_logs, %i[resource_jabvox action_jabvox],
              name: 'idx_provisioner_audit_resource'
  end
end
