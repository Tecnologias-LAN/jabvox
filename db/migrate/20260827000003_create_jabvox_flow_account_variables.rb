# frozen_string_literal: true

# Variables GLOBALES de cuenta: `{{global.<key>}}`. Persistentes, a diferencia de
# las de ejecución `{{vars.x}}`, que viven solo en memoria durante un run.
#
# SECRETOS: si `secret`, `value` guarda el payload cifrado. La API nunca devuelve
# el valor en claro; solo el motor lo descifra al resolver plantillas y lo
# redacta al persistir el paso.
class CreateJabvoxFlowAccountVariables < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_flow_account_variables do |t|
      t.references :account, null: false, foreign_key: true, index: false
      # Slug: ^[a-z][a-z0-9_]{0,48}$ — es lo que va tras `global.` en la plantilla.
      t.string :key, null: false
      t.text :value, null: false, default: ''
      t.boolean :secret, null: false, default: false
      t.string :description
      t.timestamps
    end
    add_index :jabvox_flow_account_variables, %i[account_id key], unique: true,
                                                                  name: 'idx_jabvox_flow_vars_account_key'
  end
end
