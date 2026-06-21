# == Schema Information
#
# Table name: jabvox_management_questions
#
#  id                         :bigint           not null, primary key
#  label                      :string           not null
#  options                    :jsonb            not null
#  position                   :integer          default(0), not null
#  question_type              :string           default("text"), not null
#  required                   :boolean          default(FALSE), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  jabvox_management_state_id :bigint           not null
#
# Indexes
#
#  idx_on_jabvox_management_state_id_5c2de1c51d           (jabvox_management_state_id)
#  idx_on_jabvox_management_state_id_position_5047167b84  (jabvox_management_state_id,position)
#  index_jabvox_management_questions_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_management_state_id => jabvox_management_states.id)
#
class JabvoxManagementQuestion < ApplicationRecord
  self.table_name = 'jabvox_management_questions'

  QUESTION_TYPES = %w[text number date boolean list].freeze

  belongs_to :account
  belongs_to :management_state, class_name: 'JabvoxManagementState',
                               foreign_key: :jabvox_management_state_id, inverse_of: :questions
  has_many :answers, class_name: 'JabvoxManagementAnswer', dependent: :nullify,
                     foreign_key: :jabvox_management_question_id, inverse_of: :question

  before_validation :inherit_account

  validates :label, presence: true, length: { maximum: 250 }
  validates :question_type, inclusion: { in: QUESTION_TYPES }
  validate :options_present_for_list

  scope :ordered, -> { order(:position) }

  private

  def inherit_account
    self.account_id ||= management_state&.account_id
  end

  def options_present_for_list
    return unless question_type == 'list'

    errors.add(:options, 'must have at least one option') if Array(options).reject(&:blank?).empty?
  end
end
