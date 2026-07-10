class AddLeadFiltersAndScheduleToDialerCampaigns < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_dialer_campaigns, bulk: true do |t|
      # Free-form lead filters: { q, email, phone, custom: { field_key => value } }
      t.jsonb :lead_filters_jabvox, default: {}, null: false
      # Leads unchecked in the campaign picker — always excluded from dialing.
      t.jsonb :excluded_lead_ids_jabvox, default: [], null: false
      # Management window: the campaign can only be dialed between these dates
      # (inclusive) and within calling_hours_start/end each day.
      t.date :schedule_start_date_jabvox
      t.date :schedule_end_date_jabvox
    end
  end
end
