# Materializes the dynamic management-state answers embedded in a Message/Note's
# content_attributes into normalized jabvox_management_answers rows (for reporting).
# The embedded snapshot stays the source of truth for display; this is a mirror.
class Jabvox::ManagementAnswersService
  # record: a Message or a Note carrying content_attributes.
  def initialize(record)
    @record = record
    @attributes = record.content_attributes || {}
  end

  def call
    answers = @attributes['jabvox_management_answers']
    return unless answers.is_a?(Array) && answers.any?

    state_id = @attributes['jabvox_management_state_id']
    answers.each { |answer| persist(answer, state_id) }
  rescue StandardError => e
    Rails.logger.error "[ManagementAnswers] failed for #{@record.class}##{@record.id}: #{e.message}"
  end

  private

  def persist(answer, state_id)
    JabvoxManagementAnswer.create!(
      account_id: @record.account_id,
      jabvox_management_state_id: state_id,
      jabvox_management_question_id: answer['question_id'],
      message_id: @record.is_a?(Message) ? @record.id : nil,
      note_id: @record.is_a?(Note) ? @record.id : nil,
      label: answer['label'].to_s,
      value_type: answer['type'].to_s.presence || 'text',
      value: stringify(answer['value'])
    )
  end

  def stringify(value)
    value.is_a?(Array) ? value.join(', ') : value.to_s
  end
end
