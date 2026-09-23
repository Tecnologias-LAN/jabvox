# frozen_string_literal: true

# Conversaciones del Chat Aprovisionador: resolución de la sesión activa y armado del
# historial que se manda al aprovisionador.
#
# Antes el chat era un hilo ÚNICO por cuenta y a Hermes solo se le enviaba el mensaje
# actual, así que cada turno era una conversación nueva y no recordaba nada. Aquí vive la
# lógica de sesión que corrige eso.
module JabvoxProvisioningChatSessions
  extend ActiveSupport::Concern

  # Tope de mensajes previos que se envían como contexto: acota la ventana del LLM en
  # conversaciones largas.
  MAX_HISTORY = 40

  private

  # Sesión sobre la que se opera: la que pida el cliente, o una nueva si no manda ninguna.
  def resolved_session_id
    params[:session_id].presence || new_session_id
  end

  def new_session_id
    "sess_#{SecureRandom.hex(8)}"
  end

  def latest_session_id
    Current.account.jabvox_provisioning_chat_messages.recent_first.limit(1).pick(:session_id)
  end

  # Historial de la conversación en el formato que espera el LLM ([{role:, content:}]).
  def session_history(session_id)
    Current.account.jabvox_provisioning_chat_messages
           .in_session(session_id)
           .recent_first
           .limit(MAX_HISTORY)
           .to_a
           .reverse
           .map { |m| { role: m.role, content: m.content.to_s } }
           .reject { |m| m[:content].strip.empty? }
  end

  # Modelo/proveedor elegidos en el picker (nil = el default del aprovisionador).
  def llm_overrides
    { model: params[:llm_model].presence, provider: params[:llm_provider].presence }.compact.presence
  end
end
