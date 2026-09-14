# frozen_string_literal: true

# La carga masiva del portal de afiliados pasa a procesarse en segundo plano
# (cola aislada jabvox_lead_import) en vez de dentro del request HTTP.
#
# El registro de importación necesita entonces estado propio, el archivo subido y
# el contexto que el job requiere para normalizar (país y campaña).
class AddAsyncFieldsToJabvoxAffiliateImports < ActiveRecord::Migration[7.1]
  def change
    # 0=processing, 1=completed, 2=failed. Las importaciones ya existentes se
    # crearon de forma síncrona y por definición ya terminaron: van a completed.
    add_column :jabvox_affiliate_imports, :status, :integer, null: false, default: 0
    add_column :jabvox_affiliate_imports, :country_jabvox, :string, null: false, default: ''
    add_column :jabvox_affiliate_imports, :campaign_name_jabvox, :string
    add_column :jabvox_affiliate_imports, :error_message, :string
    add_column :jabvox_affiliate_imports, :completed_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE jabvox_affiliate_imports SET status = 1, completed_at = created_at
        SQL
      end
    end

    # El portal consulta "mis importaciones recientes" del afiliado.
    add_index :jabvox_affiliate_imports, [:jabvox_affiliate_id, :created_at],
              name: 'index_jabvox_affiliate_imports_on_affiliate_and_created'
  end
end
