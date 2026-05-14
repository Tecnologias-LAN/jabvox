class AddLeadAnsweredToJabvoxDialerCallLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_dialer_call_logs, :lead_answered_jabvox, :boolean, default: false, null: false
  end
end
