json.array! @campaigns do |c|
  json.id c.id
  json.name c.name_jabvox
  json.created_at c.created_at
end
