# == Schema Information
#
# Table name: jabvox_audio_results
#
#  id                       :bigint           not null, primary key
#  anatomy_result           :jsonb            not null
#  error_message            :text
#  file_key                 :string           not null
#  final_score              :integer
#  first_pass_score         :integer
#  infaltables_applicable   :integer
#  infaltables_met          :integer
#  infaltables_result       :jsonb            not null
#  infaltables_score        :integer
#  parsed_metadata          :jsonb            not null
#  passed                   :boolean          default(FALSE), not null
#  processing_time_ms       :integer
#  qa_summary               :jsonb            not null
#  retypification_reason    :text
#  review_explanation       :text
#  review_status            :string           default("ok"), not null
#  sentiment                :string
#  stages_data              :jsonb            not null
#  status                   :string           default("pending"), not null
#  transcript               :text
#  transcript_words_jabvox  :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  advisor_id               :bigint
#  assigned_agent_id        :bigint
#  created_by_id            :bigint
#  detected_typification_id :bigint
#  job_id                   :bigint           not null
#  typification_id          :bigint
#
# Indexes
#
#  index_jabvox_audio_results_on_account_id                (account_id)
#  index_jabvox_audio_results_on_advisor_id                (advisor_id)
#  index_jabvox_audio_results_on_assigned_agent_id         (assigned_agent_id)
#  index_jabvox_audio_results_on_created_by_id             (created_by_id)
#  index_jabvox_audio_results_on_detected_typification_id  (detected_typification_id)
#  index_jabvox_audio_results_on_job_id                    (job_id)
#  index_jabvox_audio_results_on_job_id_and_file_key       (job_id,file_key)
#  index_jabvox_audio_results_on_review_status             (review_status)
#  index_jabvox_audio_results_on_typification_id           (typification_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (advisor_id => jabvox_audio_advisors.id)
#  fk_rails_...  (assigned_agent_id => users.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (detected_typification_id => jabvox_typifications.id)
#  fk_rails_...  (job_id => jabvox_audio_jobs.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxAudioResult < ApplicationRecord
  self.table_name = 'jabvox_audio_results'

  STATUSES = %w[pending processing completed error].freeze
  SENTIMENTS = %w[positive neutral negative].freeze
  REVIEW_STATUSES = %w[ok en_revision].freeze
  # Estados posibles de un infaltable, alineados con el documento de QA.
  INFALTABLE_STATUSES = %w[CUMPLE NO_CUMPLE NO_APLICA NO_VERIFICABLE].freeze
  # Estados de un criterio de Anatomía.
  ANATOMY_STATUSES = %w[LIKEU OPORTUNIDAD NO_VERIFICABLE].freeze

  belongs_to :job, class_name: 'JabvoxAudioJob', foreign_key: :job_id, inverse_of: :results
  belongs_to :account
  belongs_to :assigned_agent, class_name: 'User', optional: true
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id
  # Tipificación que la IA considera correcta (puede diferir de la asignada).
  belongs_to :detected_typification, class_name: 'JabvoxTypification', optional: true,
                                      foreign_key: :detected_typification_id
  # Asesor propio del módulo (complementa assigned_agent, que es un User del CRM).
  belongs_to :advisor, class_name: 'JabvoxAudioAdvisor', optional: true, foreign_key: :advisor_id,
                       inverse_of: :results

  validates :file_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }

  scope :in_review, -> { where(review_status: 'en_revision') }
end
