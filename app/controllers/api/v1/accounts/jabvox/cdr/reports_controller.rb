class Api::V1::Accounts::Jabvox::Cdr::ReportsController < Api::V1::Accounts::Jabvox::Cdr::BaseController
  before_action :ensure_can_view_reports, except: [:my_access]
  before_action :set_config, except: [:my_access]

  # GET /my_access — can the current user see reports, and is the module ready?
  def my_access
    render json: {
      can_view: can_view_reports?,
      is_admin: Current.account_user&.administrator? || false,
      configured: Current.account.jabvox_cdr_config&.mysql_host.present?,
      analysis_mode: Current.account.jabvox_cdr_config&.analysis_mode || 'manual',
      min_duration_seconds: Current.account.jabvox_cdr_config&.min_duration_seconds || 0
    }
  end

  # GET /records — paginated call records with filters.
  def records
    result = cdr_service.records(filter_params, page: params[:page], per_page: params[:per_page])
    render json: result
  end

  # GET /summary — per-agent aggregates.
  def summary
    render json: { summary: cdr_service.summary(filter_params) }
  end

  # POST /analyze — run (or re-run with force) AI analysis for one call synchronously.
  def analyze
    analysis = Jabvox::CdrAnalysisService.new(
      account: Current.account,
      uniqueid: params[:uniqueid],
      pipeline: pipeline_from_params,
      force: ActiveModel::Type::Boolean.new.cast(params[:force])
    ).call
    render json: serialize_analysis(analysis)
  end

  # GET /analysis/:uniqueid — fetch a stored analysis.
  def analysis
    record = Current.account.jabvox_cdr_call_analyses.find_by(uniqueid: params[:uniqueid])
    render json: record ? serialize_analysis(record) : { status: 'pending' }
  end

  # POST /analyses_batch — fetch many stored analyses at once (avoids N+1 from the table view).
  def analyses_batch
    ids = Array(params[:uniqueids]).map(&:to_s).first(200)
    records = Current.account.jabvox_cdr_call_analyses.where(uniqueid: ids)
    render json: { analyses: records.map { |r| serialize_analysis(r) } }
  end

  # GET /analysis/:uniqueid/recording — streams the call recording to the browser.
  #
  # Security: the client only sends the call's uniqueid (scoped to the account).
  # The recording file name is taken from the STORED analysis row (set server-side
  # at analysis time) — never from client input — and the bytes are proxied from
  # the PBX over SSH. The PBX host/credentials/path are never exposed to the
  # frontend, and there is no presigned/public URL to leak. The fetch happens once
  # per request and nothing is persisted.
  def recording
    record = Current.account.jabvox_cdr_call_analyses.find_by(uniqueid: params[:uniqueid])
    name = record&.recording_file_jabvox
    return render(json: { error: 'Grabación no disponible' }, status: :not_found) if name.blank?

    tmp = Jabvox::CdrRecordingService.new(@config).download(name)
    return render(json: { error: 'No se pudo obtener la grabación' }, status: :unprocessable_entity) if tmp.nil?

    send_data tmp.read, type: 'audio/mpeg', disposition: 'inline',
                        filename: File.basename(name)
  ensure
    tmp&.close!
  end

  private

  # Pass the account so the service can resolve raw PBX extensions to agent names
  # using the VoIP module's per-user extensions (source of truth).
  def cdr_service
    Jabvox::CdrMysqlService.new(@config, account: Current.account)
  end

  def set_config
    @config = Current.account.jabvox_cdr_config
    render json: { error: 'CDR no está configurado' }, status: :unprocessable_entity unless @config&.mysql_host.present?
  end

  def pipeline_from_params
    return nil if params[:pipeline_id].blank?

    Current.account.jabvox_cdr_pipelines.find_by(id: params[:pipeline_id])
  end

  def filter_params
    params.permit(:from, :to, :extension, :src, :dst, :disposition).to_h.symbolize_keys
  end

  def serialize_analysis(record)
    {
      uniqueid: record.uniqueid,
      status: record.status,
      transcript: record.transcript,
      transcript_words: record.transcript_words_jabvox,
      final_score: record.final_score,
      passed: record.passed,
      stages_data: record.stages_data,
      pipeline_id: record.pipeline_id,
      # Whether a recording can be streamed back; the file name itself is never exposed.
      has_recording: record.recording_file_jabvox.present?,
      error_message: record.error_message,
      updated_at: record.updated_at
    }
  end
end
