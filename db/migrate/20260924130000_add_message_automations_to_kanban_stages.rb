# frozen_string_literal: true

# Dos automatizaciones nuevas por columna de Kanban: mover la tarjeta cuando lleva un tiempo
# sin mensajes de ENTRADA (el cliente no responde) o sin mensajes de SALIDA (nadie le ha
# escrito).
#
# Hasta ahora el disparo por tiempo solo se medía en horas. Estos casos se necesitan también
# en minutos —"si nadie contesta en 30 minutos, escalar"—, así que el tiempo pasa a ser
# cantidad + unidad, elegible por el usuario. `trigger_hours` se conserva para las
# automatizaciones ya creadas: se lee como horas cuando no hay unidad guardada.
class AddMessageAutomationsToKanbanStages < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_kanban_stage_automations, :trigger_unit_jabvox, :string
    add_column :jabvox_kanban_stage_automations, :trigger_value_jabvox, :integer

    # Las existentes estaban en horas: se copian para que el nuevo campo sea la única
    # fuente de verdad a partir de aquí.
    execute(<<~SQL.squish)
      UPDATE jabvox_kanban_stage_automations
         SET trigger_value_jabvox = trigger_hours, trigger_unit_jabvox = 'hours'
       WHERE trigger_hours IS NOT NULL
    SQL
  end

  def down
    remove_column :jabvox_kanban_stage_automations, :trigger_unit_jabvox
    remove_column :jabvox_kanban_stage_automations, :trigger_value_jabvox
  end
end
