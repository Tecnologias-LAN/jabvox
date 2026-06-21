# == Schema Information
#
# Table name: jabvox_cdr_pipelines
#
#  id                     :bigint           not null, primary key
#  is_default             :boolean          default(FALSE), not null
#  name                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  transcription_model_id :bigint
#  typification_id        :bigint
#
# Indexes
#
#  index_jabvox_cdr_pipelines_on_account_id              (account_id)
#  index_jabvox_cdr_pipelines_on_transcription_model_id  (transcription_model_id)
#  index_jabvox_cdr_pipelines_on_typification_id         (typification_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (transcription_model_id => jabvox_ai_chat_models.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxCdrPipeline < ApplicationRecord
  self.table_name = 'jabvox_cdr_pipelines'

  belongs_to :account
  belongs_to :transcription_model, class_name: 'JabvoxAiChatModel', optional: true
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id, inverse_of: :cdr_pipelines
  has_many :stages, -> { order(:position) }, class_name: 'JabvoxCdrStage', dependent: :destroy, foreign_key: :pipeline_id,
                                             inverse_of: :pipeline
  has_many :call_analyses, class_name: 'JabvoxCdrCallAnalysis', dependent: :nullify, foreign_key: :pipeline_id, inverse_of: :pipeline

  accepts_nested_attributes_for :stages, allow_destroy: true

  validates :name, presence: true, length: { maximum: 150 }

  scope :ordered, -> { order(:name) }

  after_save :ensure_single_default, if: :saved_change_to_is_default?

  private

  def ensure_single_default
    return unless is_default?

    account.jabvox_cdr_pipelines.where.not(id: id).update_all(is_default: false)
  end
end
