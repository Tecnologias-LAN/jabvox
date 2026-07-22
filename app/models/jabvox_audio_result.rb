# == Schema Information
#
# Table name: jabvox_audio_results
#
#  id                      :bigint           not null, primary key
#  error_message           :text
#  file_key                :string           not null
#  final_score             :integer
#  passed                  :boolean          default(FALSE), not null
#  processing_time_ms      :integer
#  sentiment               :string
#  stages_data             :jsonb            not null
#  status                  :string           default("pending"), not null
#  transcript              :text
#  transcript_words_jabvox :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  assigned_agent_id       :bigint
#  created_by_id           :bigint
#  job_id                  :bigint           not null
#  typification_id         :bigint
#
# Indexes
#
#  index_jabvox_audio_results_on_account_id           (account_id)
#  index_jabvox_audio_results_on_assigned_agent_id    (assigned_agent_id)
#  index_jabvox_audio_results_on_created_by_id        (created_by_id)
#  index_jabvox_audio_results_on_job_id               (job_id)
#  index_jabvox_audio_results_on_job_id_and_file_key  (job_id,file_key)
#  index_jabvox_audio_results_on_typification_id      (typification_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assigned_agent_id => users.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (job_id => jabvox_audio_jobs.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxAudioResult < ApplicationRecord
  self.table_name = 'jabvox_audio_results'

  STATUSES = %w[pending processing completed error].freeze
  SENTIMENTS = %w[positive neutral negative].freeze

  belongs_to :job, class_name: 'JabvoxAudioJob', foreign_key: :job_id, inverse_of: :results
  belongs_to :account
  belongs_to :assigned_agent, class_name: 'User', optional: true
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id

  validates :file_key, presence: true
  validates :status, inclusion: { in: STATUSES }
end
