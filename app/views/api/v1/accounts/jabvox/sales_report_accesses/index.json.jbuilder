json.array! @accesses do |a|
  json.id a.id
  json.user_id a.user_id
  json.can_view_reports a.can_view_reports_jabvox
  json.user do
    json.id a.user.id
    json.name a.user.name
    json.email a.user.email
  end if a.user
end
