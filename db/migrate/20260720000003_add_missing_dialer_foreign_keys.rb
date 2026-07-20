# frozen_string_literal: true

# Foreign keys faltantes en tablas del dialer (auditoría D-32): evitan filas
# huérfanas y hacen que el borrado de cuenta/usuario/contacto se propague de
# forma explícita. Columnas opcionales (agent_id, contact_id) usan SET NULL para
# preservar el histórico de llamadas; las que dependen de la cuenta, CASCADE.
#
# Se añaden con validate: false y luego se validan por separado, para NO bloquear
# la tabla mientras Postgres valida las filas existentes (campaign_contacts tiene
# miles de filas en producción). validate_foreign_key toma un lock ligero.
class AddMissingDialerForeignKeys < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  FKS = [
    [:jabvox_dialer_states, :accounts, { on_delete: :cascade }],
    [:jabvox_dialer_accesses, :accounts, { on_delete: :cascade }],
    [:jabvox_dialer_accesses, :users, { on_delete: :cascade }],
    [:jabvox_dialer_state_logs, :users, { on_delete: :cascade }],
    [:jabvox_dialer_call_logs, :users, { column: :agent_id_jabvox, on_delete: :nullify }],
    [:jabvox_dialer_campaign_contacts, :contacts, { column: :contact_id, on_delete: :nullify }]
  ].freeze

  def up
    FKS.each do |from, to, opts|
      col = opts[:column] || "#{to.to_s.singularize}_id"
      add_foreign_key from, to, **opts, validate: false unless foreign_key_exists?(from, to, column: col)
      validate_foreign_key from, to, column: col
    end
  end

  def down
    FKS.each do |from, to, opts|
      col = opts[:column] || "#{to.to_s.singularize}_id"
      remove_foreign_key from, to, column: col if foreign_key_exists?(from, to, column: col)
    end
  end
end
