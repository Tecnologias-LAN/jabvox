# == Schema Information
#
# Table name: jabvox_cdr_pipelines
#
#  id                     :bigint           not null, primary key
#  is_default             :boolean          default(FALSE), not null
#  name                   :string           not null
#  segment_seconds_jabvox :integer          default(30), not null
#  timestamp_mode_jabvox  :string           default("none"), not null
#  transcription_prompt   :text
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

  # Transcript timestamp granularity requested from the transcription model.
  TIMESTAMP_MODES = %w[none word segment].freeze

  belongs_to :account
  belongs_to :transcription_model, class_name: 'JabvoxAiChatModel', optional: true
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id, inverse_of: :cdr_pipelines
  has_many :stages, -> { order(:position) }, class_name: 'JabvoxCdrStage', dependent: :destroy, foreign_key: :pipeline_id,
                                             inverse_of: :pipeline
  has_many :call_analyses, class_name: 'JabvoxCdrCallAnalysis', dependent: :nullify, foreign_key: :pipeline_id, inverse_of: :pipeline

  accepts_nested_attributes_for :stages, allow_destroy: true

  validates :name, presence: true, length: { maximum: 150 }
  validates :timestamp_mode_jabvox, inclusion: { in: TIMESTAMP_MODES }
  validates :segment_seconds_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 600 }

  scope :ordered, -> { order(:name) }

  after_save :ensure_single_default, if: :saved_change_to_is_default?
  # Mirror to the Audio Analysis module (only when both modules are enabled).
  # after_commit so stages are already persisted and the write happens outside
  # this transaction.
  after_commit :mirror_to_other_module, on: %i[create update]
  after_commit :remove_other_module_mirror, on: :destroy

  private

  def ensure_single_default
    return unless is_default?

    account.jabvox_cdr_pipelines.where.not(id: id).update_all(is_default: false)
  end

  def mirror_to_other_module
    Jabvox::PipelineSyncService.mirror(self)
  end

  def remove_other_module_mirror
    Jabvox::PipelineSyncService.remove_mirror(self)
  end
end
