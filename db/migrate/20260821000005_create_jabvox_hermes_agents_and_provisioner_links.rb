# Agentes Hermes + ligado del Hermes Aprovisionador global a cuentas.
#
# 1. jabvox_hermes_agents: un AGENTE del Hermes de una cuenta, ligado 1:1 a un usuario de
#    la app. Sus permisos SON los del usuario ligado (JabvoxHermesUserPermission) — el
#    agente solo puede hacer exactamente eso. Toda cuenta con su Hermes trae 1 agente por
#    defecto; el admin de la cuenta crea más agentes (cada uno ligado a un usuario).
#
# 2. jabvox_hermes_provisioner: el Hermes APROVISIONADOR global (uno, del super admin) que
#    se conecta una vez (URL + token de servicio cifrado) y ya sabe aprovisionar/crear más
#    Hermes. No pertenece a ninguna cuenta.
#
# 3. jabvox_hermes_provisioner_links: liga el aprovisionador global a cuentas concretas.
#    Cada cuenta ligada ve el "Chat Aprovisionador" para pedirle cosas.
class CreateJabvoxHermesAgentsAndProvisionerLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_hermes_agents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true   # ligado 1:1 a un usuario de la app
      t.string :name_jabvox, null: false                   # nombre visible del agente
      t.text :description_jabvox
      t.text :system_prompt_jabvox                          # personalidad/rol del agente
      t.boolean :is_default_jabvox, null: false, default: false
      t.string :status_jabvox, null: false, default: 'active' # active | disabled
      t.timestamps
    end
    # 1 agente por usuario y cuenta (relación 1:1 agente↔usuario dentro de la cuenta).
    add_index :jabvox_hermes_agents, %i[account_id user_id], unique: true,
              name: 'idx_hermes_agents_account_user'

    # El Hermes Aprovisionador GLOBAL (una sola fila lógica; sin account).
    create_table :jabvox_hermes_provisioners do |t|
      t.string :name_jabvox, null: false, default: 'Hermes Aprovisionador'
      t.string :base_url_jabvox                             # URL del Hermes aprovisionador
      t.text :service_token_jabvox                          # token de servicio (CIFRADO)
      t.string :status_jabvox, null: false, default: 'disconnected' # disconnected|connected|error
      t.datetime :last_check_at_jabvox
      t.text :last_error_jabvox
      t.timestamps
    end

    # Ligado del aprovisionador a cuentas concretas (cada cuenta ligada ve su chat).
    create_table :jabvox_hermes_provisioner_links do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.references :hermes_provisioner, null: false,
                                        foreign_key: { to_table: :jabvox_hermes_provisioners }
      t.string :status_jabvox, null: false, default: 'linked' # linked | unlinked
      t.timestamps
    end
  end
end
