# frozen_string_literal: true

# País (ISO) de la conexión de importación. De él sale el prefijo telefónico,
# igual que en el formulario de contacto y en el import por CSV: el prefijo
# nunca se escribe a mano ni se adivina del número.
#
# phone_prefix_jabvox se conserva para no romper conexiones ya configuradas;
# el país manda cuando está definido.
class AddCountryToJabvoxLeadSources < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_lead_sources, :country_jabvox, :string, null: false, default: ''
  end
end
