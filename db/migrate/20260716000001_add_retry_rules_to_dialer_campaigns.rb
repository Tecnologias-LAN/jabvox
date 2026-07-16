class AddRetryRulesToDialerCampaigns < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_dialer_campaigns, bulk: true do |t|
      # Which outcomes should be re-dialed (at the end of the queue) in one_by_one
      # mode. e.g. ["no_answer","busy","failed"]. Empty = never re-dial.
      t.jsonb :retry_statuses_jabvox, default: [], null: false
      # Max re-dial attempts per lead before it's given up (0 = no cap beyond one try).
      t.integer :max_retries_jabvox, default: 0, null: false
    end
  end
end
