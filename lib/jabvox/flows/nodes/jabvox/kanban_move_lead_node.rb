# frozen_string_literal: true

# jabvox.kanban.move_lead — coloca el lead en una etapa del embudo. `leadId` es
# el ID INTERNO del lead, no el número "#5" de pantalla.
class Jabvox::Flows::Nodes::Jabvox::KanbanMoveLeadNode < Jabvox::Flows::Nodes::Jabvox::KanbanBase
  type 'jabvox.kanban.move_lead'
  label 'Mover lead en Kanban'

  def perform
    funnel = find_funnel!(param(:funnelId))
    stage = find_stage_in_funnel!(param(:stageId), funnel)
    lead = find_lead!(param(:leadId))
    row, previous = place!(funnel, stage, jabvox_lead_id: lead.id)
    kanban_view(row, funnel, stage, previous)
      .merge('lead_id' => lead.id, 'leadId' => lead.id, 'lead_number' => lead.lead_number)
  end
end
