module Jabvox::NoteManagementAnswers
  extend ActiveSupport::Concern

  included do
    after_create_commit :jabvox_materialize_management_answers
  end

  private

  def jabvox_materialize_management_answers
    Jabvox::ManagementAnswersService.new(self).call
  end
end
