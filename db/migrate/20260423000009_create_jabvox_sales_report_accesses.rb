class CreateJabvoxSalesReportAccesses < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_sales_report_accesses do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.boolean :can_view_reports_jabvox, null: false, default: false
      t.timestamps
    end

    add_index :jabvox_sales_report_accesses, :account_id
    add_index :jabvox_sales_report_accesses, [:account_id, :user_id], unique: true, name: 'index_jabvox_report_access_account_user'
    add_foreign_key :jabvox_sales_report_accesses, :accounts
    add_foreign_key :jabvox_sales_report_accesses, :users
  end
end
