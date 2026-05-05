json.array! @states do |s|
  json.id s.id
  json.name_jabvox s.name_jabvox
  json.color_jabvox s.color_jabvox
  json.is_active_jabvox s.is_active_jabvox
  json.position_jabvox s.position_jabvox
  json.created_at s.created_at
  json.updated_at s.updated_at
end
