# frozen_string_literal: true

# Módulo de flujos (portado de la app NestJS "Jabvox Automations").
#
# DECISIÓN DE NOMBRES: todo va prefijado `jabvox_flow*` porque `flows` a secas
# chocaría con el vocabulario de Chatwoot y porque el resto de módulos propios ya
# usan ese prefijo. Las tablas Account y User de Prisma NO se portan: Chatwoot ya
# tiene `accounts` y `users`, y duplicarlas obligaría a sincronizar dos censos de
# identidad. Se referencian directamente por FK.
class CreateJabvoxFlows < ActiveRecord::Migration[7.1]
  def change
    create_folders
    create_flows
    create_versions
  end

  def create_folders
    create_table :jabvox_flow_folders do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.timestamps
    end
    # Nombre único por cuenta; borrar la carpeta deja sus flujos sin carpeta.
    add_index :jabvox_flow_folders, %i[account_id name], unique: true,
                                                         name: 'idx_jabvox_flow_folders_account_name'
  end

  def create_flows
    create_table :jabvox_flows do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.bigint :current_version_id
      t.bigint :folder_id
      t.timestamps
    end
    add_index :jabvox_flows, %i[account_id status], name: 'idx_jabvox_flows_account_status'
    add_index :jabvox_flows, %i[account_id folder_id], name: 'idx_jabvox_flows_account_folder'
    add_foreign_key :jabvox_flows, :jabvox_flow_folders, column: :folder_id, on_delete: :nullify
  end

  # Versión INMUTABLE del grafo: un run se ata a la versión con la que corrió,
  # así editar el flujo no reescribe la historia de lo ya ejecutado.
  def create_versions
    create_table :jabvox_flow_versions do |t|
      t.references :flow, null: false, foreign_key: { to_table: :jabvox_flows }, index: false
      t.integer :version, null: false
      t.jsonb :graph, null: false, default: {}
      t.bigint :created_by
      t.datetime :created_at, null: false
    end
    add_index :jabvox_flow_versions, %i[flow_id version], unique: true,
                                                          name: 'idx_jabvox_flow_versions_flow_version'
    add_foreign_key :jabvox_flow_versions, :users, column: :created_by, on_delete: :nullify
    add_foreign_key :jabvox_flows, :jabvox_flow_versions, column: :current_version_id, on_delete: :nullify
  end
end
