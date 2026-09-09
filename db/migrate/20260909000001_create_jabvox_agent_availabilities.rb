# Horario laboral por agente para el módulo de calendario/agenda de Jabvox IA.
# El módulo de calendario no tenía ningún concepto de disponibilidad: WorkingHour
# es por inbox, no por agente. Esta tabla define, por día de la semana, la franja
# laboral de cada agente y la duración de cita (slot) con la que se calculan los
# huecos libres que ofrece el asistente al agendar.
class CreateJabvoxAgentAvailabilities < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_agent_availabilities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # 0 = domingo … 6 = sábado (coincide con Date#wday de Ruby).
      t.integer :day_of_week, null: false
      # Minutos desde medianoche (0..1440) en la zona horaria de la cuenta.
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
      # Duración de cada cita ofrecida al calcular huecos libres.
      t.integer :slot_minutes, null: false, default: 30
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    # Una sola franja por agente y día (simple y suficiente para agenda estándar).
    add_index :jabvox_agent_availabilities,
              %i[account_id user_id day_of_week],
              unique: true,
              name: 'index_jabvox_agent_availabilities_unique'
  end
end
