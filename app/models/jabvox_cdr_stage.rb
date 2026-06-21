# == Schema Information
#
# Table name: jabvox_cdr_stages
#
#  id           :bigint           not null, primary key
#  min_score    :integer          default(0), not null
#  name         :string           not null
#  position     :integer          default(0), not null
#  prompt       :text             not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  llm_model_id :bigint
#  pipeline_id  :bigint           not null
#
# Indexes
#
#  index_jabvox_cdr_stages_on_llm_model_id              (llm_model_id)
#  index_jabvox_cdr_stages_on_pipeline_id               (pipeline_id)
#  index_jabvox_cdr_stages_on_pipeline_id_and_position  (pipeline_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (llm_model_id => jabvox_ai_chat_models.id)
#  fk_rails_...  (pipeline_id => jabvox_cdr_pipelines.id)
#
class JabvoxCdrStage < ApplicationRecord
  self.table_name = 'jabvox_cdr_stages'

  belongs_to :pipeline, class_name: 'JabvoxCdrPipeline', foreign_key: :pipeline_id, inverse_of: :stages
  belongs_to :llm_model, class_name: 'JabvoxAiChatModel', optional: true

  validates :name, presence: true, length: { maximum: 150 }
  validates :prompt, presence: true
  validates :min_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :ordered, -> { order(:position) }
end
