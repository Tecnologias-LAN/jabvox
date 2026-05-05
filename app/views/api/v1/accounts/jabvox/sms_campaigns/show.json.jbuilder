json.id @campaign.id
json.name @campaign.name
json.description @campaign.description
json.message @campaign.message
json.status @campaign.status
json.sent_count @campaign.sent_count
json.failed_count @campaign.failed_count
json.jabvox_sms_provider_id @campaign.jabvox_sms_provider_id
json.provider_name @campaign.jabvox_sms_provider&.name
json.jabvox_campaign_id @campaign.jabvox_campaign_id
json.inbox_ids_sms @campaign.inbox_ids_sms || []
json.affiliate_ids_sms @campaign.affiliate_ids_sms || []
json.created_at @campaign.created_at
json.updated_at @campaign.updated_at
