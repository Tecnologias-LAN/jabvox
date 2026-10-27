# Username de WhatsApp como campo de primera clase del contacto.
#
# Hasta ahora el username (el "@usuario" que Meta entrega en el perfil cuando el
# cliente no comparte número) solo vivía en additional_attributes.social_profiles.whatsapp.
# Se promueve a columna propia para poder mostrarlo/editarlo en la ficha, filtrarlo y
# usarlo como criterio de identidad junto al teléfono.
#
# NOTA: la columna guarda el username SIN la arroba inicial (se normaliza al escribir).
# El índice único por cuenta es PARCIAL: solo aplica cuando username no es nulo ni ''.
# Así dos contactos sin username no chocan, pero un mismo @usuario no se duplica dentro
# de una cuenta.
class AddUsernameToContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :contacts, :username, :string

    add_index :contacts, [:username, :account_id],
              unique: true,
              where: "username IS NOT NULL AND username <> ''",
              name: 'uniq_username_per_account_contact',
              algorithm: :concurrently
  end
end
