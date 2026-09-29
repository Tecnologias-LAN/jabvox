# Copiar una tarea al tablero personal del responsable cuando se le asigna.
#
# - `owner_id` en el tablero: quién es su dueño. Un tablero tiene como mucho un dueño; un
#   usuario puede ser dueño de varios (por eso la automatización guarda a cuál va).
# - `copy_to_assignee_board_jabvox` en el tablero de origen: interruptor de la automatización.
# - `jabvox_task_assignee_board_targets`: para cada dueño, a cuál de SUS tableros va la copia.
#   Sin fila para un dueño, no se copia nada suyo: la automatización no adivina destino.
# - `source_task_id` en la tarea: de qué tarea salió esta copia, para no duplicarla dos veces
#   y para poder rastrear el original.
class JabvoxTaskAssigneeBoardCopy < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_boards, :copy_to_assignee_board_jabvox, :boolean, default: false, null: false
    add_reference :jabvox_task_boards, :owner, foreign_key: { to_table: :users }, null: true, index: true

    create_table :jabvox_task_assignee_board_targets do |t|
      t.references :account, null: false, foreign_key: true
      # Tablero de origen cuya automatización está configurada.
      t.references :source_board, null: false, foreign_key: { to_table: :jabvox_task_boards }
      # Dueño al que se le copiará la tarea.
      t.references :owner, null: false, foreign_key: { to_table: :users }
      # Cuál de los tableros de ese dueño recibe la copia.
      t.references :target_board, null: false, foreign_key: { to_table: :jabvox_task_boards }
      t.timestamps
    end
    # Un único destino por (tablero de origen, dueño): sin esto una tarea se copiaría N veces.
    add_index :jabvox_task_assignee_board_targets, %i[source_board_id owner_id],
              unique: true, name: 'index_jabvox_task_targets_on_source_and_owner'

    # nullify como en recurrence_parent_id: borrar la tarea original no debe impedir
    # borrar su tablero ni arrastrarse la copia, que ya es independiente.
    add_reference :jabvox_tasks, :source_task,
                  null: true, index: true,
                  foreign_key: { to_table: :jabvox_tasks, on_delete: :nullify }
  end
end
