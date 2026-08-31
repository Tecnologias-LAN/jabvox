# frozen_string_literal: true

# jabvox.conversation.assign — asigna la conversación a un agente, a un equipo o
# a AMBOS a la vez.
#
# EL BUG QUE ESTE NODO NO PUEDE REINTRODUCIR: por HTTP la API era un if/elsif y
# mandar agente y equipo juntos ignoraba el equipo en silencio; además un id
# inexistente respondía 200 DESASIGNANDO lo que hubiera. Aquí se valida todo
# DENTRO de la cuenta antes de tocar nada: si algo no existe, no se asigna nada.
class Jabvox::Flows::Nodes::Jabvox::ConversationAssignNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.conversation.assign'
  label 'Asignar conversación'

  def perform
    conversation = find_conversation!(param(:conversationId))
    assignee, team = read_targets
    apply!(conversation, assignee, team)
    output(conversation, assignee, team)
  end

  private

  # Se resuelven ANTES de escribir: un id malo aborta el paso entero.
  def read_targets
    assignee_raw = first_filled(param(:assigneeId))
    team_raw = first_filled(param(:teamId))
    if assignee_raw.blank? && team_raw.blank?
      fail_with!('Elige al menos un destinatario: un agente, un equipo o ambos. ' \
                 'Este paso NUNCA desasigna: para quitar la asignación hazlo desde Jabvox.')
    end
    [assignee_raw.blank? ? nil : find_agent!(assignee_raw), team_raw.blank? ? nil : find_team!(team_raw)]
  end

  def find_agent!(raw)
    agent = account.users.find_by(id: raw)
    return agent if agent

    fail_with!("El agente #{raw} no existe en esta cuenta, así que no se ha asignado nada " \
               '(la conversación queda como estaba). Elige un agente de la lista del paso.')
  end

  def find_team!(raw)
    team = account.teams.find_by(id: raw)
    return team if team

    fail_with!("El equipo #{raw} no existe en esta cuenta, así que no se ha asignado nada " \
               '(la conversación queda como estaba). Elige un equipo de la lista del paso.')
  end

  # Se escriben en la MISMA operación (nada de if/elsif). Rails borra el agente
  # si no pertenece al equipo, así que se comprueba y se DESHACE todo si pasa.
  def apply!(conversation, assignee, team)
    attrs = {}
    attrs[:assignee_id] = assignee.id if assignee
    attrs[:team_id] = team.id if team
    conversation.transaction do
      conversation.update!(attrs)
      assert_assignee_survived!(conversation, assignee, team)
    end
  end

  # `fail_with!` levanta ExecutionError dentro de la transacción: eso la
  # deshace, así que la conversación queda EXACTAMENTE como estaba.
  def assert_assignee_survived!(conversation, assignee, team)
    return if assignee.nil? || conversation.assignee_id == assignee.id

    fail_with!("Jabvox descartó al agente «#{assignee.name}» porque NO es miembro del equipo " \
               "«#{team&.name}»: al asignar un equipo solo puede quedar un agente de ese equipo. " \
               'No se ha cambiado nada: añade el agente al equipo en Jabvox o asigna solo uno de los dos.')
  end

  def output(conversation, assignee, team)
    { 'conversationId' => conversation.display_id,
      'assignee_id' => conversation.assignee_id, 'assignee_name' => assignee&.name,
      'team_id' => conversation.team_id, 'team_name' => team&.name,
      'status' => conversation.status }
  end
end
