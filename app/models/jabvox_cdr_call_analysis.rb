# == Schema Information
#
# Table name: jabvox_cdr_call_analyses
#
#  id                      :bigint           not null, primary key
#  error_message           :text
#  final_score             :integer
#  passed                  :boolean          default(FALSE), not null
#  recording_file_jabvox   :string
#  stages_data             :jsonb            not null
#  status                  :string           default("pending"), not null
#  transcript              :text
#  transcript_words_jabvox :jsonb            not null
#  uniqueid                :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  created_by_id           :bigint
#  pipeline_id             :bigint
#
# Indexes
#
#  index_jabvox_cdr_call_analyses_on_account_id               (account_id)
#  index_jabvox_cdr_call_analyses_on_account_id_and_uniqueid  (account_id,uniqueid) UNIQUE
#  index_jabvox_cdr_call_analyses_on_created_by_id            (created_by_id)
#  index_jabvox_cdr_call_analyses_on_pipeline_id              (pipeline_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (pipeline_id => jabvox_cdr_pipelines.id)
#
class JabvoxCdrCallAnalysis < ApplicationRecord
  self.table_name = 'jabvox_cdr_call_analyses'

  STATUSES = %w[pending analyzing analyzed error].freeze

  belongs_to :account
  belongs_to :pipeline, class_name: 'JabvoxCdrPipeline', optional: true, foreign_key: :pipeline_id, inverse_of: :call_analyses

  validates :uniqueid, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  scope :analyzed, -> { where(status: 'analyzed') }

  def analyzed?
    status == 'analyzed'
  end
end
