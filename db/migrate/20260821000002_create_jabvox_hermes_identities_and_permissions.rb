# Hermes multi-tenant, capa segura de ejecución (Fase 0 + Fase 1).
#
# 1. jabvox_hermes_identities: identidad PROPIA del Hermes de una cuenta. Es el owner
#    (polimórfico) de un AccessToken de servicio dedicado — así Hermes NUNCA reutiliza el
#    token admin de un usuario (elimina el "Modo A: token admin en el prompt"). El token de
#    servicio se restringe y audita en un middleware de ejecución.
#
# 2. jabvox_hermes_user_permissions: permisos GRANULARES por usuario y cuenta
#    (read/create/write/delete/execute/configure/admin) que Hermes valida en backend antes
#    de ejecutar cualquier tool. El LLM nunca es la autoridad de autorización.
#
# 3. jabvox_hermes_action_logs: auditoría de cada acción ejecutada por una tool
#    (quién/cuándo/qué/resultado), sin guardar secretos ni tokens.
class CreateJabvoxHermesIdentitiesAndPermissions < ActiveRecord::Migration[7.1]
  def change
    # --- 1. Identidad de servicio del Hermes de la cuenta ---
    create_table :jabvox_hermes_identities do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :name_jabvox, null: false            # p.ej. hermes_account_50
      t.string :status_jabvox, null: false, default: 'active' # active | disabled
      t.datetime :last_seen_at_jabvox
      t.timestamps
    end

    # --- 2. Permisos granulares por usuario dentro de una cuenta ---
    create_table :jabvox_hermes_user_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # Lista de permisos concedidos: %w[read create write delete execute configure admin]
      t.jsonb :permissions_jabvox, null: false, default: []
      t.timestamps
    end
    add_index :jabvox_hermes_user_permissions, %i[account_id user_id],
              unique: true, name: 'idx_hermes_user_perms_unique'

    # --- 3. Auditoría de acciones (nunca secretos/tokens) ---
    create_table :jabvox_hermes_action_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true          # quién originó (puede ser null: cron)
      t.string :hermes_identity_jabvox               # nombre de la identidad Hermes
      t.string :tool_jabvox, null: false             # p.ej. create_tag
      t.string :permission_jabvox                    # permiso requerido por la tool
      t.jsonb :params_jabvox, default: {}            # params relevantes (sin secretos)
      t.string :status_jabvox, null: false           # success | forbidden | error
      t.text :error_jabvox
      t.integer :duration_ms_jabvox
      t.datetime :created_at, null: false
    end
    add_index :jabvox_hermes_action_logs, %i[account_id created_at]
    add_index :jabvox_hermes_action_logs, %i[account_id tool_jabvox]
  end
end
