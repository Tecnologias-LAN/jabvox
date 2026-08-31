# frozen_string_literal: true

# Base de los nodos `jabvox.kanban.*`: resuelve embudo y etapa dentro de la
# cuenta y coloca la fila del embudo respetando su unicidad.
class Jabvox::Flows::Nodes::Jabvox::KanbanBase < Jabvox::Flows::Nodes::Jabvox::Base
  private

  def find_funnel!(raw, label = 'el embudo')
    funnel_id = require_id!(raw, label)
    funnel = account.jabvox_kanban_funnels.find_by(id: funnel_id)
    return funnel if funnel

    fail_with!("El embudo #{funnel_id} no existe en esta cuenta. Elige un embudo de la lista.")
  end

  # Etapa de la cuenta Y de ESE embudo: el modelo lo valida, pero aquí el
  # mensaje dice qué embudo es el correcto.
  def find_stage_in_funnel!(raw, funnel, label = 'la etapa destino')
    stage_id = require_id!(raw, label)
    stage = account.jabvox_kanban_stages.find_by(id: stage_id)
    fail_with!("La etapa #{stage_id} no existe en esta cuenta. Elige una etapa de la lista.") if stage.nil?
    return stage if stage.jabvox_kanban_funnel_id == funnel.id

    fail_with!("La etapa \"#{stage.name_jabvox}\" pertenece a otro embudo, no a " \
               "\"#{funnel.name_jabvox}\". Elige una etapa de ese mismo embudo.")
  end

  # Unicidad por (conversación|lead, embudo): se busca la fila y se le cambia la
  # etapa en vez de crear una segunda que el modelo rechazaría.
  def place!(funnel, stage, key)
    row = JabvoxKanbanConversationStage.find_or_initialize_by(key.merge(jabvox_kanban_funnel_id: funnel.id))
    previous = row.persisted? ? row.jabvox_kanban_stage : nil
    row.account_id = account.id
    row.jabvox_kanban_stage_id = stage.id
    row.save!
    [row, previous]
  rescue ActiveRecord::RecordInvalid => e
    fail_with!("No se pudo mover en el embudo \"#{funnel.name_jabvox}\": #{e.record.errors.full_messages.join('; ')}.")
  end

  def kanban_view(row, funnel, stage, previous)
    { 'id' => row.id, 'funnel_id' => funnel.id, 'funnel_name' => funnel.name_jabvox,
      'stage_id' => stage.id, 'stage_name' => stage.name_jabvox,
      'from_stage_id' => previous&.id, 'from_stage_name' => previous&.name_jabvox,
      'moved' => previous.nil? || previous.id != stage.id }
  end
end
