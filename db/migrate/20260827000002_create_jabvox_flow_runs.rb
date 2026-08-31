# frozen_string_literal: true

# Ejecuciones de flujo y su traza por paso.
class CreateJabvoxFlowRuns < ActiveRecord::Migration[7.1]
  def change
    create_runs
    create_steps
  end

  def create_runs
    create_table :jabvox_flow_runs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :flow, null: false, foreign_key: { to_table: :jabvox_flows }, index: false
      t.bigint :version_id, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :trigger, null: false, default: {}
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at

      # PUNTERO DE REANUDACIÓN (solo runs en espera). Sin esto un run suspendido
      # queda colgado para siempre: no se sabe por qué nodo continuar ni con qué
      # contexto. `wait_state` guarda el snapshot de vars/outputs porque quien
      # reanude será OTRO proceso y no comparte memoria con este.
      t.string :waiting_node_id
      t.string :wait_reason
      t.datetime :resume_at
      t.jsonb :wait_state

      # QUIÉN lo disparó cuando fue una persona (run manual). NULL en disparos
      # de sistema; el TIPO de disparo viaja sellado dentro de `trigger`.
      t.bigint :triggered_by
      t.timestamps
    end
    add_run_indexes
  end

  def add_run_indexes
    add_index :jabvox_flow_runs, %i[account_id status], name: 'idx_jabvox_flow_runs_account_status'
    add_index :jabvox_flow_runs, %i[flow_id created_at], name: 'idx_jabvox_flow_runs_flow_created'
    # Barrido de runs vencidos: los que esperan y cuyo resume_at ya pasó.
    add_index :jabvox_flow_runs, %i[status resume_at], name: 'idx_jabvox_flow_runs_status_resume'
    add_foreign_key :jabvox_flow_runs, :jabvox_flow_versions, column: :version_id
    # SetNull: borrar un usuario no debe borrar el historial de ejecuciones.
    add_foreign_key :jabvox_flow_runs, :users, column: :triggered_by, on_delete: :nullify
  end

  def create_steps
    create_table :jabvox_flow_run_steps do |t|
      t.references :flow_run, null: false, foreign_key: { to_table: :jabvox_flow_runs }, index: false
      t.string :node_id, null: false
      t.string :node_type, null: false
      t.integer :status, null: false, default: 0
      # `input` lleva sellada la iteración del bucle bajo la clave `__bucle`,
      # para poder inspeccionar cada vuelta después sin columnas extra.
      t.jsonb :input
      t.jsonb :output
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :jabvox_flow_run_steps, %i[flow_run_id id], name: 'idx_jabvox_flow_run_steps_run'
  end
end
