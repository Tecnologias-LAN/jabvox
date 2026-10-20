class Api::V1::Accounts::Jabvox::AudioAnalysis::JobsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  # Launching an analysis job requires the manage capability.
  before_action :ensure_can_manage, only: [:create]
  before_action :set_job, only: [:show, :results]

  MAX_FILES = 500

  def index
    jobs = Current.account.jabvox_audio_jobs.recent.limit(100)
    render json: { jobs: jobs.map { |j| serialize(j) } }
  end

  # GET /jobs/:id — polled by the frontend for live progress.
  def show
    render json: serialize(@job)
  end

  def results
    rows = @job.results.includes(:assigned_agent, :typification, :advisor, :detected_typification).order(:file_key)
    render json: { results: rows.map { |r| serialize_result(r) } }
  end

  # POST /jobs — create a batch job and fan out processing.
  # rubocop:disable Metrics/AbcSize
  def create
    file_keys = Array(params[:file_keys]).map(&:to_s).reject(&:blank?).uniq.first(MAX_FILES)
    pipeline = Current.account.jabvox_audio_pipelines.find_by(id: params[:pipeline_id])
    storage = Current.account.jabvox_audio_storages.find_by(id: params[:storage_id])

    if file_keys.empty? || pipeline.nil? || storage.nil?
      render json: { error: 'pipeline_id, storage_id y file_keys son obligatorios' }, status: :unprocessable_entity
      return
    end

    job = build_job(file_keys, pipeline, storage)
    Jabvox::ProcessAudioJob.perform_later(job.id)
    render json: serialize(job), status: :created
  end
  # rubocop:enable Metrics/AbcSize

  private

  # Optional agent responsible for these audios (must belong to the account).
  def assigned_agent_id
    return nil if params[:assigned_agent_id].blank?

    Current.account.users.exists?(params[:assigned_agent_id]) ? params[:assigned_agent_id].to_i : nil
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_job(file_keys, pipeline, storage)
    fallback_agent_id = assigned_agent_id
    # Each audio's responsible agent AND typification come from its manual
    # assignment (set in the explorer); agent falls back to the job-wide agent,
    # typification falls back to the pipeline's default typification.
    assignments = Current.account.jabvox_audio_assignments
                         .where(storage_id: storage.id, file_key: file_keys)
                         .pluck(:file_key, :agent_id, :typification_id)
    agent_by_key = assignments.to_h { |key, agent, _typ| [key, agent] }
    typ_by_key = assignments.to_h { |key, _agent, typ| [key, typ] }

    # Si no hay asignación manual, el nombre del archivo se parsea contra los
    # patrones de la cuenta para vincular asesor y tipificación automáticamente.
    parser = Jabvox::AudioFilenameParserService.new(Current.account)

    # Label is generated server-side and never trusted from the client.
    job = Current.account.jabvox_audio_jobs.create!(
      pipeline: pipeline, storage: storage, created_by: current_user,
      status: 'pending', total_count: file_keys.size,
      label_jabvox: JabvoxAudioJob.next_label(Current.account)
    )
    now = Time.current
    rows = file_keys.map do |key|
      parsed = parser.parse(key)
      { job_id: job.id, account_id: Current.account.id, file_key: key, status: 'pending',
        assigned_agent_id: agent_by_key[key] || parsed[:advisor]&.user_id || fallback_agent_id,
        advisor_id: parsed[:advisor]&.id,
        typification_id: typ_by_key[key] || parsed[:typification]&.id || pipeline.typification_id,
        parsed_metadata: parsed[:raw] || {},
        stages_data: [], transcript_words_jabvox: [],
        infaltables_result: [], anatomy_result: [], qa_summary: {},
        created_at: now, updated_at: now }
    end
    JabvoxAudioResult.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
    job
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def set_job
    @job = Current.account.jabvox_audio_jobs.find(params[:id])
  end

  def serialize(job)
    {
      id: job.id,
      label: job.label_jabvox,
      status: job.status,
      pipeline_id: job.pipeline_id,
      storage_id: job.storage_id,
      total_count: job.total_count,
      processed_count: job.processed_count,
      passed_count: job.passed_count,
      failed_count: job.failed_count,
      error_count: job.error_count,
      positive_count: job.positive_count,
      neutral_count: job.neutral_count,
      negative_count: job.negative_count,
      average_score: job.average_score,
      created_at: job.created_at
    }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def serialize_result(result)
    {
      id: result.id,
      file_key: result.file_key,
      status: result.status,
      transcript: result.transcript,
      final_score: result.final_score,
      passed: result.passed,
      sentiment: result.sentiment,
      stages_data: result.stages_data,
      transcript_words: result.transcript_words_jabvox,
      error_message: result.error_message,
      processing_time_ms: result.processing_time_ms,
      assigned_agent_id: result.assigned_agent_id,
      assigned_agent_name: result.assigned_agent&.name,
      typification_id: result.typification_id,
      typification_name: result.typification&.name,
      advisor_id: result.advisor_id,
      advisor_name: result.advisor&.name,
      # Campos de QA (vacíos en pipelines no-QA).
      infaltables_result: result.infaltables_result,
      anatomy_result: result.anatomy_result,
      infaltables_score: result.infaltables_score,
      infaltables_applicable: result.infaltables_applicable,
      infaltables_met: result.infaltables_met,
      detected_typification_id: result.detected_typification_id,
      detected_typification_name: result.detected_typification&.name,
      retypification_reason: result.retypification_reason,
      qa_summary: result.qa_summary,
      review_status: result.review_status,
      review_explanation: result.review_explanation,
      first_pass_score: result.first_pass_score,
      parsed_metadata: result.parsed_metadata
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
