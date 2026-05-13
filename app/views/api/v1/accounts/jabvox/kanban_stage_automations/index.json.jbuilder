json.automations @automations do |automation|
  json.id automation.id
  json.name automation.name
  json.channel_type automation.channel_type
  json.inbox_id automation.inbox_id
  json.jabvox_email_template_id automation.jabvox_email_template_id
  json.jabvox_sms_provider_id automation.jabvox_sms_provider_id
  json.message_body automation.message_body
  json.active automation.active
  json.created_at automation.created_at
  json.updated_at automation.updated_at
end
