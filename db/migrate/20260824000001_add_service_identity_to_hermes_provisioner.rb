# frozen_string_literal: true

# Doble validación del Hermes Aprovisionador (segundo factor además del service token):
# un USUARIO de servicio real (User) ligado al provisioner + un secreto de callback. El
# webhook del aprovisionador exigirá token + service_user + secreto. Así, aunque se filtrara
# el token, sin el usuario de servicio y el secreto no se puede actuar como aprovisionador.
class AddServiceIdentityToHermesProvisioner < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_hermes_provisioners, bulk: true do |t|
      t.references :service_user, foreign_key: { to_table: :users }, null: true
      t.text :callback_secret_jabvox # cifrado en el modelo; segundo factor del webhook
      t.string :sessions_path_jabvox, default: '/api/sessions', null: false
    end
  end
end
