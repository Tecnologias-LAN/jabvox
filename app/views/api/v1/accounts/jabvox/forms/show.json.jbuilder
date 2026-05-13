json.id @form.id
json.name_jabvox @form.name_jabvox
json.slug_jabvox @form.slug_jabvox
json.active_jabvox @form.active_jabvox
json.submit_button_text_jabvox @form.submit_button_text_jabvox
json.header_jabvox @form.header_jabvox
json.footer_jabvox @form.footer_jabvox
json.fields_jabvox @form.fields_jabvox
json.submit_actions_jabvox do
  actions = @form.submit_actions_jabvox || {}
  json.email do
    json.enabled actions.dig('email', 'enabled') || false
    json.template_id actions.dig('email', 'template_id') || ''
  end
  json.webhook do
    json.enabled actions.dig('webhook', 'enabled') || false
    json.url actions.dig('webhook', 'url') || ''
    json.has_secret actions.dig('webhook', 'secret').present?
  end
  json.success do
    json.message      actions.dig('success', 'message')      || ''
    json.button_label actions.dig('success', 'button_label') || ''
    json.button_url   actions.dig('success', 'button_url')   || ''
  end
  json.privacy do
    json.enabled    actions.dig('privacy', 'enabled')    || false
    json.title      actions.dig('privacy', 'title')      || ''
    json.body       actions.dig('privacy', 'body')       || ''
    json.link_text  actions.dig('privacy', 'link_text')  || ''
    json.link_url   actions.dig('privacy', 'link_url')   || ''
    json.accept_text actions.dig('privacy', 'accept_text') || ''
  end
end
json.created_at @form.created_at
json.updated_at @form.updated_at
