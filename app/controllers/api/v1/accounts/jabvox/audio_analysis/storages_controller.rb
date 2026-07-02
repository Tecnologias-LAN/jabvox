class Api::V1::Accounts::Jabvox::AudioAnalysis::StoragesController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  # Write/config actions require the manage capability (read access is not enough).
  before_action :ensure_can_manage, only: [:create, :update, :destroy, :test, :assign]
  before_action :set_storage, only: [:update, :destroy, :objects, :assign, :playback]

  def index
    render json: { storages: Current.account.jabvox_audio_storages.order(:name).map { |s| serialize(s) } }
  end

  def create
    storage = Current.account.jabvox_audio_storages.create!(storage_params)
    render json: serialize(storage), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @storage.update!(storage_params.except(*blank_secret_keys))
    render json: serialize(@storage)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @storage.destroy!
    head :no_content
  end

  # POST /storages/test — validate credentials without saving.
  def test
    storage = Current.account.jabvox_audio_storages.new(storage_params.except(*blank_secret_keys))
    render json: Jabvox::AudioBucketService.new(storage).test_connection
  end

  # GET /storages/:id/objects?prefix= — lists the whole prefix; FE paginates.
  # Each file is enriched with its latest analysis (analyzed?, score, how many
  # stages scored it) so the browser can show a verified/score table.
  def objects
    result = Jabvox::AudioBucketService.new(@storage).list_objects(
      prefix: params[:prefix].to_s,
      search: params[:search].to_s
    )
    result[:files] = enrich_with_analysis(result[:files]) if result[:files].present?
    render json: result
  end

  # POST /storages/:id/assign — assign typification and/or agent to files without
  # launching an analysis. Supports two shapes (both valid):
  #   1) Bulk:    { file_keys: [...], typification_id, agent_id }  → same for all.
  #   2) Per-file:{ assignments: [{ file_key, typification_id, agent_id }, ...] } → one each.
  # Upserts one assignment row per file_key.
  def assign
    rows = per_file_assignments
    return render(json: { error: 'file_keys required' }, status: :unprocessable_entity) if rows.empty?

    rows.each do |row|
      record = Current.account.jabvox_audio_assignments
                      .find_or_initialize_by(storage_id: @storage.id, file_key: row[:file_key])
      record.typification_id = row[:typification_id]
      record.agent_id = row[:agent_id]
      record.save!
    end
    render json: { assigned: rows.size }
  end

  # GET /storages/:id/playback?file_key= — short-lived presigned URL to play a
  # file straight from the bucket in the browser.
  def playback
    key = params[:file_key].to_s
    return render(json: { error: 'file_key required' }, status: :unprocessable_entity) if key.blank?

    url = Jabvox::AudioBucketService.new(@storage).presigned_url(key)
    return render(json: { error: 'No se pudo generar el enlace' }, status: :unprocessable_entity) if url.blank?

    render json: { url: url }
  end

  private

  # Normalizes both assign() request shapes into [{ file_key, typification_id, agent_id }].
  def per_file_assignments
    if params[:assignments].present?
      Array(params[:assignments]).filter_map do |a|
        key = a[:file_key].to_s
        next if key.blank?

        { file_key: key, typification_id: a[:typification_id].presence, agent_id: a[:agent_id].presence }
      end
    else
      keys = Array(params[:file_keys]).map(&:to_s).reject(&:blank?)
      typification_id = params[:typification_id].presence
      agent_id = params[:agent_id].presence
      keys.map { |k| { file_key: k, typification_id: typification_id, agent_id: agent_id } }
    end
  end

  # Maps each listed file_key to its most recent analysis result + manual
  # assignment (typification/agent) for this account.
  def enrich_with_analysis(files)
    keys = files.map { |f| f[:key] }
    latest = latest_results_by_key(keys)
    assignments = assignments_by_key(keys)
    files.map do |file|
      result = latest[file[:key]]
      assignment = assignments[file[:key]]
      enriched = file
      if result
        enriched = enriched.merge(
          analyzed: result.status == 'completed',
          status: result.status,
          score: result.final_score,
          passed: result.passed,
          stages_count: Array(result.stages_data).size
        )
      end
      if assignment
        enriched = enriched.merge(
          typification_id: assignment.typification_id,
          typification_name: assignment.typification&.name,
          agent_id: assignment.agent_id,
          agent_name: assignment.agent&.name
        )
      end
      enriched
    end
  end

  def assignments_by_key(keys)
    Current.account.jabvox_audio_assignments
           .includes(:typification, :agent)
           .where(storage_id: @storage.id, file_key: keys)
           .index_by(&:file_key)
  end

  # Latest result per file_key (a file may be re-analyzed across jobs).
  def latest_results_by_key(keys)
    Current.account.jabvox_audio_results
           .where(file_key: keys)
           .order(created_at: :desc)
           .each_with_object({}) do |r, acc|
             acc[r.file_key] ||= r
           end
  end

  def set_storage
    @storage = Current.account.jabvox_audio_storages.find(params[:id])
  end

  def blank_secret_keys
    params.dig(:storage, :secret_key).blank? ? [:secret_key] : []
  end

  def storage_params
    params.require(:storage).permit(
      :name, :use_documents_config, :bucket_name, :bucket_region,
      :endpoint, :access_key, :secret_key, :path_prefix
    )
  end

  def serialize(storage)
    {
      id: storage.id,
      name: storage.name,
      use_documents_config: storage.use_documents_config,
      bucket_name: storage.bucket_name,
      bucket_region: storage.bucket_region,
      endpoint: storage.endpoint,
      access_key: storage.access_key,
      secret_key_set: storage.secret_key.present?,
      path_prefix: storage.path_prefix
    }
  end
end
