# rubocop:disable Metrics/BlockLength
json.id ticket.id
json.display_id ticket.display_id_jabvox
json.title ticket.title_jabvox
json.description ticket.description_jabvox
json.category_type ticket.category_type_jabvox
json.priority ticket.priority_jabvox
json.status ticket.status_jabvox
json.due_at ticket.due_at_jabvox
json.overdue ticket.overdue?
json.sla_status ticket.sla_status
json.minutes_to_due ticket.minutes_to_due
json.comments_count ticket.comments_count_jabvox
json.archived ticket.archived?
json.lock_version ticket.lock_version
json.first_response_at ticket.first_response_at_jabvox
json.resolved_at ticket.resolved_at_jabvox
json.closed_at ticket.closed_at_jabvox
json.resolution ticket.resolution_jabvox
json.resolution_type ticket.resolution_type_jabvox
json.satisfaction_rating ticket.satisfaction_rating_jabvox
json.satisfaction_comment ticket.satisfaction_comment_jabvox
json.reopened_count ticket.reopened_count_jabvox
json.conversation_id ticket.conversation_id
json.account_id ticket.account_id
json.created_at ticket.created_at
json.updated_at ticket.updated_at

json.category do
  if ticket.category
    json.id ticket.category.id
    json.name ticket.category.name_jabvox
    json.color ticket.category.color_jabvox
    json.category_type ticket.category.category_type_jabvox
  else
    json.null!
  end
end

json.requester do
  json.id ticket.requester.id
  json.name ticket.requester.name
  json.email ticket.requester.email
  json.avatar_url ticket.requester.avatar_url
end

json.assignee do
  if ticket.assignee
    json.id ticket.assignee.id
    json.name ticket.assignee.name
    json.avatar_url ticket.assignee.avatar_url
  else
    json.null!
  end
end

json.contact do
  if ticket.contact
    json.id ticket.contact.id
    json.name ticket.contact.name
  else
    json.null!
  end
end

if local_assigns[:detailed]
  json.activities ticket.activities.chronological do |activity|
    json.id activity.id
    json.action activity.action_jabvox
    json.from activity.from_value_jabvox
    json.to activity.to_value_jabvox
    json.metadata activity.metadata_jabvox
    json.user_name activity.user&.name
    json.created_at activity.created_at
  end

  json.attachments ticket.attachments do |att|
    json.id att.id
    json.filename att.filename.to_s
    json.url Rails.application.routes.url_helpers.rails_blob_url(att, only_path: true)
    json.byte_size att.byte_size
  end
end
# rubocop:enable Metrics/BlockLength
