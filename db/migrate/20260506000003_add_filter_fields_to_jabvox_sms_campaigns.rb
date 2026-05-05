class AddFilterFieldsToJabvoxSmsCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_sms_campaigns, :jabvox_campaign_id, :bigint
    add_column :jabvox_sms_campaigns, :inbox_ids_sms, :jsonb, default: []
    add_column :jabvox_sms_campaigns, :affiliate_ids_sms, :jsonb, default: []
    add_foreign_key :jabvox_sms_campaigns, :jabvox_campaigns, column: :jabvox_campaign_id,
                    on_delete: :nullify, validate: false
  end
end
