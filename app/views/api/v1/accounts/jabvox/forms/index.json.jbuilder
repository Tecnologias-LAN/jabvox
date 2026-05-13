json.array! @forms do |form|
  json.id form.id
  json.name_jabvox form.name_jabvox
  json.slug_jabvox form.slug_jabvox
  json.active_jabvox form.active_jabvox
  json.submit_button_text_jabvox form.submit_button_text_jabvox
  json.header_jabvox form.header_jabvox
  json.footer_jabvox form.footer_jabvox
  json.fields_jabvox form.fields_jabvox
  json.submit_actions_jabvox do
    actions = form.submit_actions_jabvox || {}
    json.email do
      json.enabled actions.dig('email', 'enabled') || false
      json.to actions.dig('email', 'to') || ''
    end
    json.sms do
      json.enabled actions.dig('sms', 'enabled') || false
      json.to actions.dig('sms', 'to') || ''
    end
    json.webhook do
      json.enabled actions.dig('webhook', 'enabled') || false
      json.url actions.dig('webhook', 'url') || ''
      json.has_secret actions.dig('webhook', 'secret').present?
    end
  end
  json.created_at form.created_at
  json.updated_at form.updated_at
end
