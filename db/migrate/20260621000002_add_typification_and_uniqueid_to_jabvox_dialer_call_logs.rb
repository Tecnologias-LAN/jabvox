class AddTypificationAndUniqueidToJabvoxDialerCallLogs < ActiveRecord::Migration[7.1]
  def change
    # Lets dialer calls carry a typification (same JabvoxTypification used by click-to-call)
    # and link back to the PBX CDR/recording via uniqueid, so dialer calls feed the same
    # CDR reports column and analysis pipelines.
    add_reference :jabvox_dialer_call_logs, :typification,
                  foreign_key: { to_table: :jabvox_typifications }, null: true
    add_column :jabvox_dialer_call_logs, :uniqueid_jabvox, :string
    add_index :jabvox_dialer_call_logs, [:account_id, :uniqueid_jabvox]
  end
end
