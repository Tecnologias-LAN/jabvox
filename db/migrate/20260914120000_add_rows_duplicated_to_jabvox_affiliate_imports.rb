# frozen_string_literal: true

# Filas que el afiliado subió pero no se montaron por ser leads que ya existen
# en la cuenta (mismo teléfono o mismo correo). Se separan de rows_failed porque
# un duplicado no es un error del archivo: es un lead que ya estaba.
class AddRowsDuplicatedToJabvoxAffiliateImports < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_affiliate_imports, :rows_duplicated, :integer, null: false, default: 0
  end
end
