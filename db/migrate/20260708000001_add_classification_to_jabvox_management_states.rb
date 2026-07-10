class AddClassificationToJabvoxManagementStates < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_management_states, bulk: true do |t|
      # "Estado" — the group a substate belongs to (Llamada, Whatsapp, …).
      # The existing name_jabvox becomes the "Subestado".
      t.string :state_group_jabvox, default: '', null: false
      # "¿En qué caso se usa?" — guidance shown to the agent when picking.
      t.text :usage_info_jabvox, default: '', null: false
      t.boolean :managed_jabvox, default: true, null: false            # Gestionado
      t.boolean :contact_jabvox, default: false, null: false           # Contacto
      t.boolean :effective_contact_jabvox, default: false, null: false # Contacto efectivo
      t.boolean :advisory_jabvox, default: false, null: false          # Asesoría
      t.string :service_type_jabvox, default: 'No', null: false        # Es servicio
      t.integer :positivity_level_jabvox, default: 0, null: false      # Estado más positivo (0-100)
    end

    add_index :jabvox_management_states, [:account_id, :state_group_jabvox],
              name: 'idx_jabvox_mgmt_states_on_account_and_group'
  end
end
