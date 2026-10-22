# frozen_string_literal: true

# Posición de la tarjeta DENTRO de su columna (etapa) del kanban. Permite reordenar
# tarjetas arriba/abajo manualmente y que el orden se persista. Índice por
# (etapa, posición) para traerlas ordenadas por columna sin ordenar en memoria.
class AddPositionToJabvoxKanbanConversationStages < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_kanban_conversation_stages, :position_jabvox, :integer, default: 0, null: false
    add_index :jabvox_kanban_conversation_stages, %i[jabvox_kanban_stage_id position_jabvox],
              name: 'idx_jabvox_conv_stages_stage_position'
  end
end
