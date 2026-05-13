json.templates @templates do |template|
  json.id template.id
  json.name template.name
  json.subject template.subject
  json.body template.body
  json.active template.active
  json.created_at template.created_at
  json.updated_at template.updated_at
end
json.meta do
  json.count @templates.size
  json.limit JabvoxEmailTemplate.limit_for(Current.account)
end
