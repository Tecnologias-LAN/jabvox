json.array! @tax_rates do |r|
  json.id r.id
  json.name_jabvox r.name_jabvox
  json.percentage_jabvox r.percentage_jabvox
  json.active_jabvox r.active_jabvox
  json.created_at r.created_at
end
