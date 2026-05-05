json.funnel do
  json.id @board[:funnel].id
  json.name_jabvox @board[:funnel].name_jabvox
  json.description_jabvox @board[:funnel].description_jabvox
  json.active_jabvox @board[:funnel].active_jabvox
end

json.stages @board[:stages] do |stage_data|
  stage = stage_data[:stage]
  json.id stage.id
  json.name_jabvox stage.name_jabvox
  json.color_jabvox stage.color_jabvox
  json.position_jabvox stage.position_jabvox
  json.description_jabvox stage.description_jabvox

  json.conversations stage_data[:conversations] do |conversation|
    json.id conversation.id
    json.display_id conversation.display_id
    json.uuid conversation.uuid
    json.status conversation.status
    json.priority conversation.priority
    json.created_at conversation.created_at
    json.updated_at conversation.updated_at
    json.last_activity_at conversation.last_activity_at

    json.contact do
      contact = conversation.contact
      json.id contact.id
      json.name jabvox_mask('name', contact.name)
      json.email jabvox_mask('email', contact.email)
      json.phone_number jabvox_mask('phone', contact.phone_number)
      json.avatar_url contact.avatar_url
    end

    json.assignee do
      if conversation.assignee
        json.id conversation.assignee.id
        json.name conversation.assignee.name
        json.avatar_url conversation.assignee.avatar_url
      else
        json.null!
      end
    end

    json.inbox do
      json.id conversation.inbox.id
      json.name conversation.inbox.name
      json.channel_type conversation.inbox.channel_type
    end

    json.labels conversation.labels
  end
end
