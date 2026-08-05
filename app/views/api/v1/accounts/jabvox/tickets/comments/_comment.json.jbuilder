json.id comment.id
json.body comment.body_jabvox
json.private comment.private_jabvox
json.ticket_id comment.ticket_id
json.created_at comment.created_at
json.user do
  json.id comment.user.id
  json.name comment.user.name
  json.avatar_url comment.user.avatar_url
end
