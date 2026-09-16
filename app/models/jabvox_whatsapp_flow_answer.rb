# == Schema Information
#
# Table name: jabvox_whatsapp_flow_answers
#
#  id                                 :bigint           not null, primary key
#  component_name                     :string           not null
#  component_type                     :string           not null
#  value_text                         :text
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  component_id                       :string           not null
#  jabvox_whatsapp_flow_submission_id :bigint           not null
#  screen_id                          :string           not null
#
# Indexes
#
#  idx_jabvox_wa_flow_answers_on_submission_id           (jabvox_whatsapp_flow_submission_id)
#  index_jabvox_whatsapp_flow_answers_on_component_name  (component_name)
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_whatsapp_flow_submission_id => jabvox_whatsapp_flow_submissions.id)
#
class JabvoxWhatsappFlowAnswer < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_flow_answers'

  belongs_to :submission, class_name: 'JabvoxWhatsappFlowSubmission',
                           foreign_key: :jabvox_whatsapp_flow_submission_id, inverse_of: :answers

  validates :screen_id, presence: true
  validates :component_id, presence: true
  validates :component_name, presence: true
  validates :component_type, presence: true

  scope :by_component_name, ->(name) { where(component_name: name) if name.present? }
end
