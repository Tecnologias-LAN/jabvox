# frozen_string_literal: true

# jabvox.state.set_management_state — registra un estado de gestión sobre la
# conversación. En Jabvox eso NO es un campo: es una NOTA PRIVADA con el estado
# en `content_attributes.jabvox_management_state_name` (así lo leen el detalle
# del lead, el histórico y los informes).
class Jabvox::Flows::Nodes::Jabvox::StateSetManagementStateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.state.set_management_state'
  label 'Registrar estado de gestión'

  # Origen de la gestión. El modelo exige marca de origen en toda gestión con
  # estado; sin esto quedaría como 'unknown' en los informes.
  CALL_SOURCE = 'automation'

  def perform
    state_name = param(:state).to_s.strip
    fail_with!('Falta el "Estado de gestión": elige uno de la lista de estados de la cuenta.') if state_name.blank?

    conversation = find_conversation!(param(:conversationId))
    state = account.jabvox_management_states.find_by(name_jabvox: state_name)
    message = create_note(conversation, state_name, state)
    output(conversation, message, state_name, state)
  end

  private

  def create_note(conversation, state_name, state)
    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id,
      content: first_filled(param(:note), "Estado de gestión: #{state_name}"),
      message_type: :outgoing, private: true,
      content_attributes: content_attributes(state_name, state)
    )
  end

  # Si el estado existe en la cuenta se guarda la MISMA foto que escribe la UI
  # (grupo, color, clasificación); si es texto libre, solo el nombre.
  def content_attributes(state_name, state)
    base = { 'jabvox_management_state_name' => state_name, 'jabvox_call_source' => CALL_SOURCE }
    return base if state.nil?

    base.merge(
      'jabvox_management_state_id' => state.id,
      'jabvox_management_state_group' => state.state_group_jabvox,
      'jabvox_management_state_color' => state.color_jabvox,
      'jabvox_management_note_mode' => state.note_mode,
      'jabvox_management_managed' => state.managed_jabvox,
      'jabvox_management_contact' => state.contact_jabvox,
      'jabvox_management_effective_contact' => state.effective_contact_jabvox,
      'jabvox_management_advisory' => state.advisory_jabvox,
      'jabvox_management_service_type' => state.service_type_jabvox,
      'jabvox_management_positivity_level' => state.positivity_level_jabvox
    )
  end

  # `known_state` en false avisa de que el estado se registró como texto libre:
  # no coincide con ninguno de la cuenta y los informes por estado no lo verán.
  def output(conversation, message, state_name, state)
    { 'conversationId' => conversation.display_id, 'id' => message.id,
      'state' => state_name, 'state_id' => state&.id, 'known_state' => !state.nil?,
      'content' => message.content, 'private' => true,
      'created_at' => message.created_at.iso8601 }
  end
end
