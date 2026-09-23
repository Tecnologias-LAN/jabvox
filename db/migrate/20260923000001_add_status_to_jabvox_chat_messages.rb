# frozen_string_literal: true

# Estado del turno en los dos chats (IA y Aprovisionador).
#
# Hasta ahora un mensaje del asistente solo se guardaba si el turno había producido texto o
# herramientas: si el usuario salía del chat mientras el agente trabajaba, o el turno quedaba
# esperando una aprobación, NO se escribía nada y al volver el historial aparecía incompleto
# — la respuesta se perdía sin rastro.
#
# Con `status_jabvox` el mensaje se crea al arrancar el turno y se va actualizando, así que al
# volver al chat siempre hay una fila que dice en qué quedó: 'streaming' (en proceso),
# 'waiting_approval' (pendiente de aprobar), 'completed', 'interrupted' o 'failed'.
class AddStatusToJabvoxChatMessages < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_ai_chat_messages, :status_jabvox, :string
    add_column :jabvox_provisioning_chat_messages, :status_jabvox, :string

    # Lo ya existente terminó (o se perdió, pero no está en curso): marcarlo completed evita
    # que el frontend muestre turnos antiguos como si siguieran corriendo.
    execute("UPDATE jabvox_ai_chat_messages SET status_jabvox = 'completed' WHERE status_jabvox IS NULL")
    execute("UPDATE jabvox_provisioning_chat_messages SET status_jabvox = 'completed' WHERE status_jabvox IS NULL")

    # Se consulta "el último turno de esta sesión y su estado" al abrir el chat.
    add_index :jabvox_ai_chat_messages, %i[session_id_jabvox status_jabvox],
              name: 'idx_jabvox_ai_chat_on_session_status'
    add_index :jabvox_provisioning_chat_messages, %i[session_id status_jabvox],
              name: 'idx_jabvox_prov_chat_on_session_status'
  end

  def down
    remove_index :jabvox_ai_chat_messages, name: 'idx_jabvox_ai_chat_on_session_status'
    remove_index :jabvox_provisioning_chat_messages, name: 'idx_jabvox_prov_chat_on_session_status'
    remove_column :jabvox_ai_chat_messages, :status_jabvox
    remove_column :jabvox_provisioning_chat_messages, :status_jabvox
  end
end
