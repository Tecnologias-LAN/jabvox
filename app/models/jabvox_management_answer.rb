# == Schema Information
#
# Table name: jabvox_management_answers
#
#  id                            :bigint           not null, primary key
#  label                         :string           default(""), not null
#  value                         :text
#  value_type                    :string           default("text"), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  jabvox_management_question_id :bigint
#  jabvox_management_state_id    :bigint
#  message_id                    :bigint
#  note_id                       :bigint
#
# Indexes
#
#  idx_on_jabvox_management_question_id_65239e4ba3                (jabvox_management_question_id)
#  index_jabvox_management_answers_on_account_id                  (account_id)
#  index_jabvox_management_answers_on_jabvox_management_state_id  (jabvox_management_state_id)
#  index_jabvox_management_answers_on_message_id                  (message_id)
#  index_jabvox_management_answers_on_note_id                     (note_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_management_question_id => jabvox_management_questions.id) ON DELETE => nullify
#  fk_rails_...  (jabvox_management_state_id => jabvox_management_states.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (note_id => notes.id)
#
class JabvoxManagementAnswer < ApplicationRecord
  self.table_name = 'jabvox_management_answers'

  belongs_to :account
  belongs_to :management_state, class_name: 'JabvoxManagementState',
                               foreign_key: :jabvox_management_state_id, optional: true, inverse_of: false
  belongs_to :question, class_name: 'JabvoxManagementQuestion',
                       foreign_key: :jabvox_management_question_id, optional: true, inverse_of: :answers
  belongs_to :message, optional: true
  belongs_to :note, optional: true
end
