# frozen_string_literal: true

# Orden de las tarjetas por columna en el tablero de Tareas (igual que en Kanban).
# 'manual' = orden por arrastre (position_jabvox); el resto ordena en cliente.
class AddCardSortToJabvoxTaskStages < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_stages, :card_sort_jabvox, :string, default: 'manual', null: false
  end
end
