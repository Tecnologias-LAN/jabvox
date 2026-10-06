# Secciones de Configuración que no se podían apagar por cuenta: estaban siempre visibles
# aunque el cliente no las usara. Van con default true para no quitarle nada a nadie al
# desplegar: quien ya las tenía las conserva, y el Super Admin puede apagarlas por cuenta.
class AddModuleTogglesForSettingsSections < ActiveRecord::Migration[7.1]
  def change
    change_table :accounts, bulk: true do |t|
      t.boolean :jabvox_ip_whitelist_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_management_states_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_field_security_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_conversation_workflow_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_sla_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_audit_logs_enabled_jabvox, null: false, default: true
      t.boolean :jabvox_canned_responses_enabled_jabvox, null: false, default: true
    end
  end
end
