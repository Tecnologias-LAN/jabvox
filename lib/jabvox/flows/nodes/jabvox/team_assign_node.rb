# frozen_string_literal: true

# jabvox.team.assign — asigna la conversación a un equipo.
#
# EL BUG QUE ESTE NODO NO PUEDE REINTRODUCIR: por HTTP un team_id inexistente
# respondía 200 DESASIGNANDO el equipo que hubiera, y el nodo reportaba éxito.
# Aquí el equipo se valida DENTRO de la cuenta: si no existe no se toca nada.
class Jabvox::Flows::Nodes::Jabvox::TeamAssignNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.team.assign'
  label 'Asignar a equipo'

  def perform
    conversation = find_conversation!(param(:conversationId))
    team = find_team!(first_filled(param(:teamId)))
    previous_assignee_id = conversation.assignee_id
    conversation.update!(team_id: team.id)
    output(conversation, team, previous_assignee_id)
  end

  private

  def find_team!(raw)
    team_id = require_id!(raw, 'el "Equipo"')
    team = account.teams.find_by(id: team_id)
    return team if team

    fail_with!("El equipo #{team_id} no existe en esta cuenta, así que no se ha asignado nada " \
               '(la conversación conserva el equipo que tuviera). Elige un equipo de la lista del paso.')
  end

  # Rails quita al agente asignado si no es miembro del equipo nuevo. No es un
  # error, pero se declara en la salida para que no sea una sorpresa silenciosa.
  def output(conversation, team, previous_assignee_id)
    { 'conversationId' => conversation.display_id, 'team_id' => conversation.team_id,
      'team_name' => team.name, 'assignee_id' => conversation.assignee_id,
      'assignee_removed' => previous_assignee_id.present? && conversation.assignee_id.nil?,
      'status' => conversation.status }
  end
end
