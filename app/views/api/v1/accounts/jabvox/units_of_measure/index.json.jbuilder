json.array! @units do |u|
  json.id u.id
  json.name_jabvox u.name_jabvox
  json.abbreviation_jabvox u.abbreviation_jabvox
  json.active_jabvox u.active_jabvox
  json.created_at u.created_at
end
