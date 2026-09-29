# frozen_string_literal: true

# Tareas que se repiten (semanal, mensual, anual) y etapas con un papel definido.
#
# La recurrencia es "al completar": cuando una tarea recurrente se marca como hecha se crea
# la siguiente con la fecha desplazada. Se eligió frente a generar por calendario porque no
# acumula duplicados de lo que nadie cerró; a cambio, la tarea vencida sin completar se
# manda a la etapa inactiva para que se vea que se dejó pasar.
#
# El papel va en la ETAPA, no en tres columnas del tablero: así cada etapa sabe qué es y
# añadir etapas intermedias no obliga a tocar la configuración del tablero.
class AddRecurrenceToJabvoxTasks < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_tasks, bulk: true do |t|
      # Vacío = tarea normal. Con valor = se repite cada N unidades al completarse.
      t.string :recurrence_unit_jabvox
      t.integer :recurrence_count_jabvox, default: 1, null: false
      # Deja de repetirse pasada esta fecha (opcional).
      t.datetime :recurrence_until_jabvox
      # Encadena las copias con la tarea que las originó, para poder ver la serie completa
      # y para no repetir el aviso dos veces sobre la misma ocurrencia.
      t.bigint :recurrence_parent_id
      # Cuándo se avisó por última vez de esta ocurrencia: sin esto el recordatorio se
      # mandaría en cada pasada del cron.
      t.datetime :reminder_sent_at_jabvox
    end

    add_index :jabvox_tasks, :recurrence_parent_id
    add_index :jabvox_tasks, [:account_id, :recurrence_unit_jabvox],
              name: 'index_jabvox_tasks_on_account_and_recurrence',
              where: 'recurrence_unit_jabvox IS NOT NULL'
    add_foreign_key :jabvox_tasks, :jabvox_tasks, column: :recurrence_parent_id, on_delete: :nullify

    # Papel de la etapa dentro del flujo: initial (donde nace la tarea), done (completada)
    # e inactive (se dejó pasar). NULL = etapa intermedia normal.
    add_column :jabvox_task_stages, :role_jabvox, :string
    add_index :jabvox_task_stages, [:board_id, :role_jabvox],
              unique: true,
              where: 'role_jabvox IS NOT NULL',
              name: 'index_jabvox_task_stages_on_board_and_role'
  end
end
