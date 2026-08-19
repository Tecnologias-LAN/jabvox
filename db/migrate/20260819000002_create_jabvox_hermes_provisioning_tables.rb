# frozen_string_literal: true

# Integración Hermes + ContextForge por cuenta (aislada por tenant).
#
# - jabvox_ai_chat_provisioning_enabled_jabvox: módulo "Chat Aprovisionamiento" en la cuenta
#   (donde se le pide a Hermes crear MCPs y, la 1ª vez, aprovisionar su Hermes/ContextForge).
# - jabvox_context_forge_handoffs: el handoff que deja el Provisioner para que el Consumer
#   de la cuenta arranque — base_url, virtual_server_id y scoped_token (CIFRADO). Uno por cuenta.
# - jabvox_provisioning_chat_messages: historial del chat de aprovisionamiento de la cuenta.
# - jabvox_ai_chat_models.source/hermes_model_id: para el sync BIDIRECCIONAL de modelos
#   entre el ai-chat de la cuenta y el Hermes de la cuenta.
class CreateJabvoxHermesProvisioningTables < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_ai_chat_provisioning_enabled_jabvox, :boolean,
               default: false, null: false

    create_table :jabvox_context_forge_handoffs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      # Estado del aprovisionamiento de la cuenta en ContextForge/Hermes.
      # pending: ligada pero aún sin aprovisionar. provisioning: en curso.
      # ready: Hermes+virtual server+token listos. failed: falló (ver last_error).
      t.string :status, default: 'pending', null: false
      t.string :contextforge_base_url          # base del gateway ContextForge de la cuenta
      t.string :virtual_server_id              # virtual server que agrupa SOLO las MCPs de la cuenta
      t.string :team_id                        # team de la cuenta en ContextForge
      t.string :hermes_instance_id             # instancia Hermes creada "desde 0" para la cuenta
      t.text   :scoped_token                   # token con alcance SOLO a ese virtual server (CIFRADO)
      t.jsonb  :mcp_servers, default: [], null: false  # MCPs de la cuenta [{id,name,kind,status}]
      t.string :last_error
      t.datetime :provisioned_at
      t.timestamps
    end

    create_table :jabvox_provisioning_chat_messages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true   # quién pidió (para auditoría + permisos)
      t.string :role, null: false                          # user | assistant | system
      t.text   :content
      t.jsonb  :metadata, default: {}, null: false         # tool calls, mcp creado, etc.
      t.timestamps
    end
    add_index :jabvox_provisioning_chat_messages, [:account_id, :created_at]

    change_table :jabvox_ai_chat_models, bulk: true do |t|
      # 'local' = configurado en el ai-chat de la cuenta; 'hermes' = importado del Hermes
      # de la cuenta por el sync bidireccional.
      t.string :source_jabvox, default: 'local', null: false
      t.string :hermes_model_id_jabvox     # id del modelo en Hermes (para el sync)
    end
  end
end
