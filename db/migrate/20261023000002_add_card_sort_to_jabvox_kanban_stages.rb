# frozen_string_literal: true

# Preferencia de ordenamiento de las tarjetas DENTRO de cada columna del kanban,
# recordada en BD (no hardcodeada). Valores: 'manual' (orden arrastrado, por
# position_jabvox), 'number_asc' (# de menor a mayor), 'number_desc' (# de mayor a
# menor). Default 'manual' para respetar el orden que el usuario arrastró.
class AddCardSortToJabvoxKanbanStages < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_kanban_stages, :card_sort_jabvox, :string, default: 'manual', null: false
  end
end
