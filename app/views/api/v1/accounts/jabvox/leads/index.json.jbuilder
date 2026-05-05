# rubocop:disable Metrics/BlockLength
json.data do
  json.array! @leads do |lead|
    conv = @conv_data[lead.contact_id] || {}
    c = lead.contact

    json.id lead.id
    json.lead_number lead.lead_number
    json.created_at lead.created_at

    json.contact do
      json.id c.id
      json.name jabvox_mask('name', c.name)
      json.email jabvox_mask('email', c.email)
      json.phone_number jabvox_mask('phone', c.phone_number)
      json.avatar_url c.avatar_url
      json.country c.additional_attributes&.dig('country')
    end

    json.campaign do
      if lead.jabvox_campaign
        json.id lead.jabvox_campaign.id
        json.name lead.jabvox_campaign.name_jabvox
      else
        json.null!
      end
    end

    json.inbox_id conv[:inbox_id]
    json.inbox_name conv[:inbox_name]
    json.assignee_id lead.assignee_id
    json.assignee_name lead.assignee&.name
    json.conversation_id conv[:conversation_id]
    json.last_management_state conv[:last_management_state]
    json.last_management_at conv[:last_management_at]
    json.is_sold_jabvox lead.is_sold_jabvox
    json.affiliate_id lead.jabvox_affiliate_id
    json.affiliate_name lead.jabvox_affiliate&.name
  end
end
# rubocop:enable Metrics/BlockLength

json.meta do
  json.total @total
  json.current_page @leads.current_page
  json.total_pages @leads.total_pages
end

json.filter_options @filter_options
