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
    json.conversation_display_id conv[:conversation_display_id]
    json.last_management_state conv[:last_management_state]
    json.last_management_at conv[:last_management_at]
    json.last_management_source conv[:last_management_source]
    # All managements for this lead within the active date range (historic view),
    # newest-first: each with its state, medium (jabvox_call_source) and agent, so
    # the row can expand to show every gestión of the day, not just the latest.
    json.managements(@managements_by_contact&.dig(lead.contact_id) || []) do |m|
      json.state m.state
      json.source m.source
      json.at m.at
      json.agent_name m.agent_name
      json.origin m.origin
    end
    # Per-lead counts for the summary columns.
    json.managements_count(@management_counts_by_contact&.dig(lead.contact_id) || 0)
    json.typifications_count(@typification_counts&.dig(lead.id) || 0)
    json.is_sold_jabvox lead.is_sold_jabvox
    json.affiliate_id lead.jabvox_affiliate_id
    json.affiliate_name lead.jabvox_affiliate&.name
    # Custom fields of the lead, so the table can render swappable custom columns
    # (already loaded on the row — no extra query).
    json.custom_fields lead.custom_fields_jabvox || {}
  end
end
# rubocop:enable Metrics/BlockLength

json.meta do
  json.total @total
  json.current_page @leads.current_page
  json.total_pages @leads.total_pages
  # Global total of managements across the whole filter (all matching leads within
  # the date range), for the "X gestiones en total" summary above the list.
  json.total_managements @management_total
end

# Only present on the first page (static per session); the frontend caches it and
# reuses it while paginating, so later pages skip the 6 filter-option queries.
json.filter_options @filter_options if @filter_options
