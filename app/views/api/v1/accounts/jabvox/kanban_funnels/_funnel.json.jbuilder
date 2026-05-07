json.id funnel.id
json.name_jabvox funnel.name_jabvox
json.description_jabvox funnel.description_jabvox
json.position_jabvox funnel.position_jabvox
json.active_jabvox funnel.active_jabvox
json.account_id funnel.account_id
json.created_at funnel.created_at
json.updated_at funnel.updated_at

json.inbox_ids funnel.jabvox_kanban_funnel_inboxes.pluck(:inbox_id)
json.campaign_ids funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
json.affiliate_ids funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
json.include_own_leads funnel.include_own_leads_jabvox

json.stages funnel.jabvox_kanban_stages.ordered do |stage|
  json.id stage.id
  json.name_jabvox stage.name_jabvox
  json.description_jabvox stage.description_jabvox
  json.position_jabvox stage.position_jabvox
  json.color_jabvox stage.color_jabvox
end
