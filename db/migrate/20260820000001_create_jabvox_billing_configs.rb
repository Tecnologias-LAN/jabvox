# frozen_string_literal: true

class CreateJabvoxBillingConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_billing_configs do |t|
      t.integer :unpaid_account_cleanup_days, null: false, default: 7
      t.timestamps
    end
  end
end
