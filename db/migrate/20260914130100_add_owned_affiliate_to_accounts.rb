# frozen_string_literal: true

# "Afiliado propio" de cada cuenta.
#
# Todo lead que NO llega por un afiliado externo (alta manual, importación por
# CSV, importación desde BD externa, o una conversación nueva) queda atribuido a
# este afiliado, para que el módulo de Afiliados muestre siempre de dónde salió
# cada lead en vez de dejar un hueco.
#
# Vive en base de datos, NO hardcodeado: es una fila normal de jabvox_affiliates
# marcada con owned_jabvox. El índice único garantiza que cada cuenta tenga como
# máximo uno, y el modelo impide renombrarlo, desactivarlo o borrarlo — ni desde
# la interfaz ni desde la API.
class AddOwnedAffiliateToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_affiliates, :owned_jabvox, :boolean, null: false, default: false
    add_index :jabvox_affiliates, :account_id,
              unique: true, where: 'owned_jabvox = true',
              name: 'index_jabvox_affiliates_one_owned_per_account'

    # Se crea el afiliado propio de las cuentas que ya tienen el módulo activo.
    # Las demás lo reciben la primera vez que se consulta la lista.
    say_with_time 'Creando el afiliado propio de las cuentas existentes' do
      Account.find_each { |account| create_owned_for(account) }
    end
  end

  def down
    remove_index :jabvox_affiliates, name: 'index_jabvox_affiliates_one_owned_per_account'
    remove_column :jabvox_affiliates, :owned_jabvox
  end

  private

  def create_owned_for(account)
    return if JabvoxAffiliate.exists?(account_id: account.id, owned_jabvox: true)

    JabvoxAffiliate.create!(account: account, name: 'Propio', owned_jabvox: true, active: true)
  rescue StandardError => e
    Rails.logger.warn("[AddOwnedAffiliateToAccounts] cuenta=#{account.id}: #{e.message}")
  end
end
