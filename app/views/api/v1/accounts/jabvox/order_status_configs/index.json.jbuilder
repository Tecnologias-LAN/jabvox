json.array! @status_configs do |s|
  json.id s.id
  json.key_jabvox s.key_jabvox
  json.label_jabvox s.label_jabvox
  json.sort_order_jabvox s.sort_order_jabvox
  json.color_jabvox s.color_jabvox
  json.created_at s.created_at
  json.updated_at s.updated_at
end
