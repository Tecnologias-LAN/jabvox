# frozen_string_literal: true

# Modelo de SESIÓN del Chat IA. Antes la sesión era "virtual" (filas de
# jabvox_ai_chat_messages con el mismo session_id_jabvox) y no tenía título propio.
# Esta tabla le da identidad: título renombrable y la conexión/agente que la atiende.
# No borra nada existente; las sesiones viejas siguen funcionando sin fila aquí (el
# front cae al rótulo "Sesión N").
class CreateJabvoxAiChatSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_ai_chat_sessions do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :session_id_jabvox, null: false, limit: 100
      t.string :title_jabvox
      t.bigint :connection_id

      t.timestamps
    end

    # El historial del Chat IA es PRIVADO POR USUARIO: la sesión se identifica por
    # (cuenta, usuario, session_id). El índice único impide duplicar la fila de sesión en un
    # find_or_create concurrente del mismo usuario.
    add_index :jabvox_ai_chat_sessions, %i[account_id user_id session_id_jabvox],
              unique: true, name: 'idx_jabvox_ai_chat_sessions_uniq'
    add_index :jabvox_ai_chat_sessions, :account_id
    add_index :jabvox_ai_chat_sessions, :user_id

    add_foreign_key :jabvox_ai_chat_sessions, :accounts, column: :account_id
    add_foreign_key :jabvox_ai_chat_sessions, :users, column: :user_id
  end
end
