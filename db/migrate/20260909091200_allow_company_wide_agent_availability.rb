# Permite horario de EMPRESA (por defecto) en jabvox_agent_availabilities:
# una fila con user_id NULL representa la franja general de la cuenta, que se usa
# como fallback para los agentes que no tienen horario propio configurado.
class AllowCompanyWideAgentAvailability < ActiveRecord::Migration[7.1]
  def up
    change_column_null :jabvox_agent_availabilities, :user_id, true

    # El índice único existente trata cada NULL como distinto (Postgres), así que
    # no garantiza un solo horario de empresa por día. Añadimos un índice único
    # parcial para las filas de empresa (user_id IS NULL).
    add_index :jabvox_agent_availabilities, %i[account_id day_of_week],
              unique: true,
              where: 'user_id IS NULL',
              name: 'index_jabvox_agent_availabilities_company_unique'
  end

  def down
    remove_index :jabvox_agent_availabilities, name: 'index_jabvox_agent_availabilities_company_unique'
    change_column_null :jabvox_agent_availabilities, :user_id, false
  end
end
