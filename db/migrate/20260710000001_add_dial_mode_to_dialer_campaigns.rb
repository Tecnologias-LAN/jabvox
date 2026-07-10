class AddDialModeToDialerCampaigns < ActiveRecord::Migration[7.1]
  def change
    # last_state = dial leads whose LAST management state matches the filter
    #              (historical behavior).
    # one_by_one = walk every matching lead once, never re-dialing a lead already
    #              attempted in this campaign, until none are left.
    add_column :jabvox_dialer_campaigns, :dial_mode_jabvox, :string,
               default: 'last_state', null: false
  end
end
