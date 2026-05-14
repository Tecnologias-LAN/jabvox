class AddWaitInQueueToJabvoxDialerCampaigns < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_dialer_campaigns, :wait_in_queue_jabvox, :boolean, default: true, null: false
  end
end
