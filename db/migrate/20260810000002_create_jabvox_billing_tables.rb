# frozen_string_literal: true

# Sistema de cobro y aprovisionamiento por pago (fuente de verdad = app Jabvox):
#   - jabvox_plans: catálogo de planes editable desde Super Admin.
#   - jabvox_payment_gateway_configs: selección de pasarela activa + tokens PÚBLICOS
#     (los secretos viven en .env, nunca aquí).
#   - jabvox_provisioning_transactions: una fila por intento de pago→aprovisionamiento,
#     con su estado, motivo y clave de idempotencia.
# Además, en accounts: el plan vigente y su fecha de expiración.
class CreateJabvoxBillingTables < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :price_cents, null: false, default: 0
      t.string :currency, null: false, default: 'COP'
      t.integer :duration_days, null: false, default: 30
      t.jsonb :modules, null: false, default: []           # nombres cortos de módulos Jabvox
      t.jsonb :chatwoot_features, null: false, default: []  # features nativas de Chatwoot
      t.jsonb :limits, null: false, default: {}             # inboxes, agents, forms, etc.
      t.string :whatsapp_number
      t.integer :status, null: false, default: 0            # 0=draft, 1=active, 2=in_development
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :jabvox_plans, :slug, unique: true
    add_index :jabvox_plans, :status

    create_table :jabvox_payment_gateway_configs do |t|
      t.string :provider, null: false                       # bold | wompi | mono
      t.boolean :active, null: false, default: false
      t.string :public_token                                # token/llave PÚBLICA (no secreta)
      t.string :checkout_base_url
      t.jsonb :settings, null: false, default: {}           # datos NO sensibles de la pasarela
      t.timestamps
    end
    add_index :jabvox_payment_gateway_configs, :provider, unique: true
    # Solo una pasarela activa a la vez (índice parcial).
    add_index :jabvox_payment_gateway_configs, :active, unique: true, where: 'active = true',
                                                        name: 'idx_one_active_gateway'

    create_table :jabvox_provisioning_transactions do |t|
      t.references :account, foreign_key: true, null: true  # null si la cuenta aún no existe
      t.references :jabvox_plan, foreign_key: true, null: true
      t.string :buyer_email
      t.string :gateway, null: false                        # bold | wompi | mono
      t.string :gateway_reference                           # id del pago en la pasarela
      t.string :idempotency_key, null: false
      t.integer :amount_cents
      t.string :currency, default: 'COP'
      t.integer :status, null: false, default: 0
      t.string :status_reason
      t.integer :attempts, null: false, default: 0
      t.jsonb :payload, null: false, default: {}            # payload SANEADO de la pasarela
      t.datetime :payment_approved_at
      t.datetime :provisioned_at
      t.timestamps
    end
    add_index :jabvox_provisioning_transactions, :idempotency_key, unique: true
    add_index :jabvox_provisioning_transactions, :gateway_reference
    add_index :jabvox_provisioning_transactions, :status

    add_column :accounts, :jabvox_plan_id, :bigint
    add_column :accounts, :jabvox_plan_expires_at, :datetime
    add_index :accounts, :jabvox_plan_id
  end
end
