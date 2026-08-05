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

json.attachments comment.attachments do |att|
  json.id att.id
  json.filename att.filename.to_s
  json.url Rails.application.routes.url_helpers.rails_blob_url(att, only_path: true)
  json.byte_size att.byte_size
end
