json.array! @item_types do |t|
  json.id t.id
  json.name_jabvox t.name_jabvox
  json.active_jabvox t.active_jabvox
  json.created_at t.created_at
end
