json.array! @providers do |provider|
  json.id provider.id
  json.name provider.name
  json.base_url provider.base_url
  json.api_user provider.api_user
  json.has_password provider.api_password.present?
  json.active provider.active
  json.created_at provider.created_at
end
