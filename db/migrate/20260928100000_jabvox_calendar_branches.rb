# frozen_string_literal: true

# Sedes del calendario: una cuenta puede atender en varios sitios (sede, consultorio,
# sucursal… el nombre lo pone cada cliente) y cada uno tiene su horario y su zona horaria.
#
# El horario funciona en dos niveles, que es como se organiza de verdad una agenda:
#   - la SEDE abre de 6 a 18
#   - cada AGENTE cubre un tramo dentro de ese horario (6 a 12), y el resto lo cubre otro
#     o no lo cubre nadie
#
# La disponibilidad pasa a colgar de la sede y admite varias franjas por día: hasta ahora
# un índice único por (cuenta, usuario, día) impedía la pausa de comida, que es lo primero
# que necesita cualquier consultorio.
class JabvoxCalendarBranches < ActiveRecord::Migration[7.1]
  def up
    create_table :jabvox_branches do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name_jabvox, null: false
      # Zona IANA ('America/Bogota'). Es lo que decide a qué hora local abre la sede.
      t.string :timezone_jabvox, null: false, default: 'UTC'
      t.string :color_jabvox, null: false, default: '#6366F1'
      t.text :address_jabvox
      t.boolean :active_jabvox, null: false, default: true
      t.integer :position_jabvox, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :jabvox_branches, %i[account_id name_jabvox], unique: true

    # Responsables de la sede: informativo, no concede permisos. Puede no haber ninguno.
    create_table :jabvox_branch_managers do |t|
      t.references :branch, null: false, foreign_key: { to_table: :jabvox_branches }, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :jabvox_branch_managers, %i[branch_id user_id], unique: true

    # Horario comercial de la sede, una fila por día y franja (admite jornada partida).
    create_table :jabvox_branch_hours do |t|
      t.references :branch, null: false, foreign_key: { to_table: :jabvox_branches }, index: false
      t.integer :day_of_week, null: false
      t.integer :open_minute, null: false
      t.integer :close_minute, null: false
      t.timestamps
    end
    add_index :jabvox_branch_hours, %i[branch_id day_of_week]

    # La disponibilidad del agente pasa a ser por sede, y deja de estar limitada a una
    # franja por día: los índices únicos antiguos lo impedían.
    add_reference :jabvox_agent_availabilities, :branch,
                  foreign_key: { to_table: :jabvox_branches }, index: true
    remove_index :jabvox_agent_availabilities, name: 'index_jabvox_agent_availabilities_unique'
    remove_index :jabvox_agent_availabilities, name: 'index_jabvox_agent_availabilities_company_unique'
    add_index :jabvox_agent_availabilities, %i[account_id branch_id user_id day_of_week],
              name: 'index_jabvox_availabilities_lookup'

    # Sede de la cita. Nullable: las que ya existen no tienen sede y siguen valiendo.
    add_reference :jabvox_calendar_events, :branch,
                  foreign_key: { to_table: :jabvox_branches }, index: true

    # Quién creó la cita, para auditoría: hasta ahora `user_id` hacía de dueño y de
    # creador a la vez, así que tras editarla no quedaba rastro de quién la abrió.
    add_reference :jabvox_calendar_events, :created_by,
                  foreign_key: { to_table: :users }, index: true
  end

  def down
    remove_reference :jabvox_calendar_events, :created_by, foreign_key: { to_table: :users }
    remove_reference :jabvox_calendar_events, :branch, foreign_key: { to_table: :jabvox_branches }
    remove_index :jabvox_agent_availabilities, name: 'index_jabvox_availabilities_lookup'
    remove_reference :jabvox_agent_availabilities, :branch, foreign_key: { to_table: :jabvox_branches }
    add_index :jabvox_agent_availabilities, %i[account_id user_id day_of_week],
              name: 'index_jabvox_agent_availabilities_unique', unique: true
    add_index :jabvox_agent_availabilities, %i[account_id day_of_week],
              name: 'index_jabvox_agent_availabilities_company_unique',
              unique: true, where: '(user_id IS NULL)'
    drop_table :jabvox_branch_hours
    drop_table :jabvox_branch_managers
    drop_table :jabvox_branches
  end
end
