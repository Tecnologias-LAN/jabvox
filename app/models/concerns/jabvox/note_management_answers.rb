module Jabvox::NoteManagementAnswers
  extend ActiveSupport::Concern

  included do
    before_validation :jabvox_ensure_call_source
    after_create_commit :jabvox_materialize_management_answers
  end

  private

  def jabvox_materialize_management_answers
    Jabvox::ManagementAnswersService.new(self).call
  end

  # A note that carries a management state must always record its origin; if a
  # creation path forgot to set it, default to 'unknown' so the export never
  # loses the "from where" trace. Only touches management notes.
  def jabvox_ensure_call_source
    return unless respond_to?(:content_attributes)

    attrs = content_attributes
    return unless attrs.is_a?(Hash)
    return if attrs['jabvox_management_state_id'].blank?
    return if attrs['jabvox_call_source'].present?

    self.content_attributes = attrs.merge('jabvox_call_source' => 'unknown')
  end
end
