json.array! @currencies do |c|
  json.id c.id
  json.symbol_jabvox c.symbol_jabvox
  json.name_jabvox c.name_jabvox
  json.active_jabvox c.active_jabvox
  json.created_at c.created_at
end
