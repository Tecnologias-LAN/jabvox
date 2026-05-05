json.array! @discounts do |d|
  json.id d.id
  json.name_jabvox d.name_jabvox
  json.description_jabvox d.description_jabvox
  json.percentage_jabvox d.percentage_jabvox
  json.active_jabvox d.active_jabvox
  json.created_at d.created_at
  json.updated_at d.updated_at
end
