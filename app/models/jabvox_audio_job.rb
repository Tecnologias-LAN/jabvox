# == Schema Information
#
# Table name: jabvox_audio_jobs
#
#  id              :bigint           not null, primary key
#  average_score   :integer
#  error_count     :integer          default(0), not null
#  failed_count    :integer          default(0), not null
#  label_jabvox    :string
#  negative_count  :integer          default(0), not null
#  neutral_count   :integer          default(0), not null
#  passed_count    :integer          default(0), not null
#  positive_count  :integer          default(0), not null
#  processed_count :integer          default(0), not null
#  status          :string           default("pending"), not null
#  total_count     :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#  pipeline_id     :bigint
#  storage_id      :bigint
#
# Indexes
#
#  index_jabvox_audio_jobs_on_account_and_label  (account_id,label_jabvox)
#  index_jabvox_audio_jobs_on_account_id         (account_id)
#  index_jabvox_audio_jobs_on_created_by_id      (created_by_id)
#  index_jabvox_audio_jobs_on_pipeline_id        (pipeline_id)
#  index_jabvox_audio_jobs_on_storage_id         (storage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (pipeline_id => jabvox_audio_pipelines.id)
#  fk_rails_...  (storage_id => jabvox_audio_storages.id)
#
class JabvoxAudioJob < ApplicationRecord
  self.table_name = 'jabvox_audio_jobs'

  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :account
  belongs_to :pipeline, class_name: 'JabvoxAudioPipeline', optional: true, foreign_key: :pipeline_id, inverse_of: :jobs
  belongs_to :storage, class_name: 'JabvoxAudioStorage', optional: true, foreign_key: :storage_id, inverse_of: :jobs
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :results, class_name: 'JabvoxAudioResult', dependent: :destroy, foreign_key: :job_id, inverse_of: :job

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  LABEL_PREFIX = 'analisis'.freeze
  LABEL_PATTERN = /\Aanalisis(\d+)\z/

  # Server-generated incremental label per account: analisis1, analisis2, …
  # Derived from the highest existing number so it can't be spoofed or set by the client.
  def self.next_label(account)
    last = account.jabvox_audio_jobs
                  .where("label_jabvox ~ ?", '^analisis[0-9]+$')
                  .pluck(:label_jabvox)
                  .filter_map { |l| l[LABEL_PATTERN, 1]&.to_i }
                  .max || 0
    "#{LABEL_PREFIX}#{last + 1}"
  end

  # Recomputes counters from results and flips status to completed when done.
  def refresh_progress!
    stats = results.group(:status).count
    processed = (stats['completed'] || 0) + (stats['error'] || 0)
    passed = results.where(status: 'completed', passed: true).count
    failed = results.where(status: 'completed', passed: false).count
    sentiments = results.where(status: 'completed').group(:sentiment).count
    avg = results.where(status: 'completed').where.not(final_score: nil).average(:final_score)

    update!(
      processed_count: processed,
      passed_count: passed,
      failed_count: failed,
      error_count: stats['error'] || 0,
      positive_count: sentiments['positive'] || 0,
      neutral_count: sentiments['neutral'] || 0,
      negative_count: sentiments['negative'] || 0,
      average_score: avg&.round,
      status: processed >= total_count ? 'completed' : 'processing'
    )
  end
end
