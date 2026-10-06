# Modo "N avisos cada X antes del vencimiento": en vez de un ciclo indefinido, la
# automatización se agenda hacia atrás desde la fecha de la tarea. "3 veces cada 2 horas
# antes" manda avisos a -6h, -4h y -2h, y termina sola al llegar el vencimiento. La fecha
# de fin es la de la tarea, así que no hay que configurarla aparte.
class AddBeforeDueModeToTaskAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_automations, :schedule_mode_jabvox, :string,
               null: false, default: 'recurring'
  end
end
