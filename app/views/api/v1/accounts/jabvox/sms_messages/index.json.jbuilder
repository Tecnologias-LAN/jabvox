json.data do
  json.array! @messages do |msg|
    json.id msg.id
    json.phone msg.phone
    json.message msg.message
    json.status msg.status
    json.external_id msg.external_id
    json.error_message msg.error_message
    json.sent_at msg.sent_at
    json.created_at msg.created_at
    json.campaign_id msg.jabvox_sms_campaign_id
    json.campaign_name msg.jabvox_sms_campaign&.name
    json.contact_name msg.contact&.name
  end
end
json.meta do
  json.total @total
  json.current_page @messages.current_page
  json.total_pages @messages.total_pages
end
