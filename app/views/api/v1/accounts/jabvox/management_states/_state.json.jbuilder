json.id state.id
json.name_jabvox state.name_jabvox
json.state_group_jabvox state.state_group_jabvox
json.usage_info_jabvox state.usage_info_jabvox
json.managed_jabvox state.managed_jabvox
json.contact_jabvox state.contact_jabvox
json.effective_contact_jabvox state.effective_contact_jabvox
json.advisory_jabvox state.advisory_jabvox
json.service_type_jabvox state.service_type_jabvox
json.positivity_level_jabvox state.positivity_level_jabvox
json.color_jabvox state.color_jabvox
json.is_active_jabvox state.is_active_jabvox
json.position_jabvox state.position_jabvox
json.note_mode state.note_mode
json.questions state.questions.ordered do |question|
  json.id question.id
  json.label question.label
  json.question_type question.question_type
  json.options question.options
  json.required question.required
  json.position question.position
  json.visibility question.visibility
  json.lead_field question.lead_field
  json.lead_field_locked question.lead_field_locked
end
json.created_at state.created_at
json.updated_at state.updated_at
