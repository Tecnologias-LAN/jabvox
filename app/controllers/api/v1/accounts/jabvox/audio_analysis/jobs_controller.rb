class Api::V1::Accounts::Jabvox::AudioAnalysis::JobsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
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
    rows = @job.results.includes(:assigned_agent).order(:file_key)
    render json: { results: rows.map { |r| serialize_result(r) } }
  end

  # POST /jobs — create a batch job and fan out processing.
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

  private

  # Optional agent responsible for these audios (must belong to the account).
  def assigned_agent_id
    return nil if params[:assigned_agent_id].blank?

    Current.account.users.exists?(params[:assigned_agent_id]) ? params[:assigned_agent_id].to_i : nil
  end

  def build_job(file_keys, pipeline, storage)
    fallback_agent_id = assigned_agent_id
    # Each audio's responsible agent comes from its manual assignment
    # (set in the explorer); fall back to the optional job-wide agent.
    agent_by_key = Current.account.jabvox_audio_assignments
                          .where(storage_id: storage.id, file_key: file_keys)
                          .pluck(:file_key, :agent_id).to_h
    job = Current.account.jabvox_audio_jobs.create!(
      pipeline: pipeline, storage: storage, created_by: current_user,
      status: 'pending', total_count: file_keys.size
    )
    rows = file_keys.map do |key|
      { job_id: job.id, account_id: Current.account.id, file_key: key, status: 'pending',
        assigned_agent_id: agent_by_key[key] || fallback_agent_id, stages_data: [],
        created_at: Time.current, updated_at: Time.current }
    end
    JabvoxAudioResult.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
    job
  end

  def set_job
    @job = Current.account.jabvox_audio_jobs.find(params[:id])
  end

  def serialize(job)
    {
      id: job.id,
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
      error_message: result.error_message,
      processing_time_ms: result.processing_time_ms,
      assigned_agent_id: result.assigned_agent_id,
      assigned_agent_name: result.assigned_agent&.name
    }
  end
end
