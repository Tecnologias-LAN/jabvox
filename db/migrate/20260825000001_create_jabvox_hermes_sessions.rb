# frozen_string_literal: true

# Sesión de Hermes por (cuenta + usuario), igual que Telegram mapea chat_id → sesión.
# Guarda el session_id que devuelve POST /api/sessions para reutilizarlo en cada turno
# (POST /api/sessions/{id}/chat) y así mantener conversación continua. `kind` distingue el
# Chat IA de la cuenta ('account') del Chat Aprovisionador ('provisioner').
class CreateJabvoxHermesSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_hermes_sessions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind_jabvox, null: false, default: 'account'
      t.string :session_id_jabvox
      t.datetime :last_used_at_jabvox
      t.timestamps
    end
    # Una sesión por (cuenta, usuario, tipo) — reutilizable e idempotente.
    add_index :jabvox_hermes_sessions, %i[account_id user_id kind_jabvox], unique: true,
                                                                           name: 'idx_hermes_sessions_account_user_kind'
  end
end
