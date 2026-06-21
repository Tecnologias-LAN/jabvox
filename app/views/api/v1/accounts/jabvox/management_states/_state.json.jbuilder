json.id state.id
json.name_jabvox state.name_jabvox
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
end
json.created_at state.created_at
json.updated_at state.updated_at
