# Mapeos configurables (desde la visual) que traducen un código extraído del
# nombre de archivo a una tipificación o a un asesor, SIN que el código lo asuma.
# Ej.: "AMP" -> tipificación "Asesoría en momento de pedido";
#      "Gisell Martínez" -> asesor Gisell. Si un código no está mapeado, el parser
# deja la llamada sin tipificación/asesor hasta que el usuario lo configure.
class CreateAudioCodeMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_audio_code_mappings do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      # 'typification' o 'advisor'.
      t.string :kind, null: false
      # El valor tal cual aparece en el nombre de archivo (campaign o nombre).
      t.string :code, null: false
      t.bigint :typification_id
      t.bigint :advisor_id
      t.bigint :created_by_id
      t.timestamps
    end
    # Un código no puede mapear a dos cosas del mismo tipo en la misma cuenta.
    add_index :jabvox_audio_code_mappings, %i[account_id kind code], unique: true,
                                                                     name: 'index_audio_code_mappings_on_account_kind_code'
    add_foreign_key :jabvox_audio_code_mappings, :jabvox_typifications, column: :typification_id
    add_foreign_key :jabvox_audio_code_mappings, :jabvox_audio_advisors, column: :advisor_id
    add_foreign_key :jabvox_audio_code_mappings, :users, column: :created_by_id
  end
end
