# Una automatización por tiempo solo paraba si tenía `end_at_jabvox`, un campo que ni
# siquiera estaba en el formulario: en la práctica no paraba nunca. Con intervalos de horas
# eso son decenas de envíos al día a un contacto real. `max_runs_jabvox` permite acotarla
# por cantidad además de por fecha.
class AddMaxRunsToTaskAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_automations, :max_runs_jabvox, :integer
  end
end
