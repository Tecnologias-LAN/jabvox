require 'openai'

# Analyzes a single call: download recording -> transcribe (Whisper) -> run each
# pipeline stage through an LLM -> compute final score. Result is persisted on a
# JabvoxCdrCallAnalysis row (unique per uniqueid per account) and cached.
class Jabvox::CdrAnalysisService
  TRANSCRIBE_TIMEOUT = 120
  MAX_AUDIO_BYTES = 25 * 1024 * 1024

  # Raised with a specific, user-facing reason so the agent sees WHY transcription failed
  # (missing model, no recording, download error, …) instead of a generic message.
  TranscriptionError = Class.new(StandardError)

  def initialize(account:, uniqueid:, pipeline: nil, force: false)
    @account = account
    @uniqueid = uniqueid.to_s
    @pipeline = pipeline
    @force = force
    @config = account.jabvox_cdr_config
  end

  def call
    analysis = JabvoxCdrCallAnalysis.find_or_initialize_by(account_id: @account.id, uniqueid: @uniqueid)
    return analysis if !@force && analysis.analyzed?

    return fail!(analysis, 'CDR no está configurado para esta cuenta.') unless @config

    pipeline = resolve_pipeline
    return fail!(analysis, 'No hay un pipeline de análisis configurado.') unless pipeline
    return fail!(analysis, 'Las grabaciones (SSH/SFTP) no están configuradas.') unless @config.recordings_configured?

    analysis.update!(status: 'analyzing', pipeline_id: pipeline.id, error_message: nil)
    run(analysis, pipeline)
  rescue TranscriptionError => e
    Rails.logger.warn "[CDR] transcription failed for #{@uniqueid}: #{e.message}"
    fail!(analysis, e.message)
  rescue StandardError => e
    Rails.logger.error "[CDR] analysis failed for #{@uniqueid}: #{e.class}: #{e.message}"
    fail!(analysis, "Error al analizar: #{e.message}")
  end

  private

  def run(analysis, pipeline)
    transcript, words = transcribe(pipeline)
    raise TranscriptionError, 'La transcripción quedó vacía.' if transcript.blank?

    stages_data = pipeline.stages.map { |stage| run_stage(stage, transcript) }
    scores = stages_data.filter_map { |s| s[:score] }
    final_score = scores.empty? ? nil : (scores.sum / scores.size)
    passed = stages_data.all? { |s| s[:passed] }

    analysis.update!(
      transcript: transcript,
      transcript_words_jabvox: words || [],
      recording_file_jabvox: @recording_name,
      stages_data: stages_data,
      final_score: final_score,
      passed: passed,
      status: 'analyzed',
      error_message: nil
    )
    analysis
  end

  def resolve_pipeline
    @pipeline ||
      pipeline_from_typification ||
      @config.default_pipeline ||
      @account.jabvox_cdr_pipelines.find_by(is_default: true) ||
      @account.jabvox_cdr_pipelines.first
  end

  # If this recording maps to a typified call (click-to-call OR dialer, via uniqueid),
  # prefer the pipeline configured for that typification.
  def pipeline_from_typification
    typification_id =
      @account.jabvox_call_logs.where(uniqueid: @uniqueid).where.not(typification_id: nil).pick(:typification_id) ||
      @account.jabvox_dialer_call_logs.where(uniqueid_jabvox: @uniqueid).where.not(typification_id: nil).pick(:typification_id)
    return nil unless typification_id

    @account.jabvox_cdr_pipelines.find_by(typification_id: typification_id)
  end

  # Returns [transcript_text, words_array]. words_array is [] unless the pipeline
  # requests timestamps (per-word or per-segment).
  def transcribe(pipeline)
    model = transcription_model(pipeline)
    tmp = download_recording
    transcribe_audio(model, tmp, pipeline)
  ensure
    tmp&.close!
  end

  # Resolves the transcription model, raising a specific reason if unavailable.
  def transcription_model(pipeline)
    model = pipeline.transcription_model || @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    raise TranscriptionError, no_model_message if model.nil?
    raise TranscriptionError, 'El modelo de transcripción no tiene API key configurada.' if model.api_key_jabvox.blank?

    model
  end

  # Fetches the recording into a temp file, raising a specific reason on each failure point.
  # Stashes the resolved file name so the analysis row can reference it for playback.
  def download_recording
    recording_name = Jabvox::CdrMysqlService.new(@config).recording_file(@uniqueid)
    raise TranscriptionError, 'La llamada no tiene grabación registrada en el PBX (campo recordingfile vacío).' if recording_name.blank?

    @recording_name = recording_name
    tmp = Jabvox::CdrRecordingService.new(@config).download(recording_name)
    raise TranscriptionError, download_failed_message(recording_name) if tmp.nil?
    raise TranscriptionError, 'La grabación supera el tamaño máximo permitido (25 MB).' if tmp.size > MAX_AUDIO_BYTES

    tmp
  end

  def no_model_message
    'No hay un modelo de transcripción configurado (asigna uno al pipeline o marca un modelo de IA por defecto).'
  end

  def download_failed_message(recording_name)
    "No se pudo descargar la grabación del PBX (#{recording_name}). Revisa el acceso SSH y la ruta de grabaciones."
  end

  # Transcribes the recording, returning [text, words]. Words are requested only
  # when the pipeline asks for timestamps. See AudioAnalysisService for the
  # multipart "timestamp_granularities[]" caveat.
  def transcribe_audio(model, file, pipeline)
    client = openai_client(model)
    mode = pipeline.timestamp_mode_jabvox
    params = { model: transcription_model_name(model), file: file, language: 'es' }

    if mode == 'none'
      response = client.audio.transcribe(parameters: params)
      return [response['text'].presence, []]
    end

    params[:response_format] = 'verbose_json'
    params[:'timestamp_granularities[]'] = 'word'
    response = client.audio.transcribe(parameters: params)
    text = response['text'].presence
    word_list = Array(response['words']).map do |w|
      { 'word' => w['word'], 'start' => w['start'], 'end' => w['end'] }
    end
    if word_list.empty?
      word_list = Array(response['segments']).map do |s|
        { 'word' => s['text'].to_s.strip, 'start' => s['start'], 'end' => s['end'] }
      end
    end
    words = mode == 'segment' ? group_into_segments(word_list, pipeline) : word_list
    [text, words]
  rescue Faraday::Error, OpenAI::Error => e
    raise TranscriptionError, "El servicio de transcripción rechazó la solicitud: #{e.message}"
  end

  # Buckets per-word timings into fixed segments of N seconds.
  def group_into_segments(word_list, pipeline)
    span = pipeline.segment_seconds_jabvox.to_i
    span = 30 if span <= 0
    word_list.group_by { |w| (w['start'].to_f / span).floor }
             .map do |bucket, words|
               { 'start' => bucket * span, 'end' => (bucket + 1) * span,
                 'word' => words.map { |w| w['word'] }.join(' ').strip }
             end
  end

  # The Whisper-style transcription model name; falls back to whisper-1.
  def transcription_model_name(model)
    name = model.model_jabvox.to_s
    name.match?(/whisper|transcribe/i) ? name : 'whisper-1'
  end

  def run_stage(stage, transcript)
    model = stage.llm_model || stage.pipeline.transcription_model ||
            @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    return stage_error(stage, 'Sin modelo LLM') unless model

    parsed = call_llm(model, stage.prompt, transcript)
    score = parsed['score'].to_i
    {
      stage_id: stage.id,
      name: stage.name,
      score: score,
      min_score: stage.min_score,
      passed: score >= stage.min_score,
      reasoning: parsed['reasoning'].to_s,
      highlights: Array(parsed['highlights']),
      issues: Array(parsed['issues'])
    }
  rescue StandardError => e
    stage_error(stage, e.message)
  end

  def call_llm(model, prompt, transcript)
    client = openai_client(model)
    response = client.chat(
      parameters: {
        model: model.model_jabvox,
        temperature: 0.3,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system_prompt(prompt) },
          { role: 'user', content: transcript }
        ]
      }
    )
    JSON.parse(response.dig('choices', 0, 'message', 'content').to_s)
  end

  def system_prompt(stage_prompt)
    "#{stage_prompt}\n\n" \
      'Responde SOLO con un objeto JSON con las claves: ' \
      '"score" (entero 0-100), "reasoning" (string), ' \
      '"highlights" (array de strings), "issues" (array de strings).'
  end

  def openai_client(model)
    options = { access_token: model.api_key_jabvox.to_s, request_timeout: TRANSCRIBE_TIMEOUT }
    base = model.base_url_jabvox.presence
    options[:uri_base] = base if base
    OpenAI::Client.new(**options)
  end

  def stage_error(stage, message)
    { stage_id: stage.id, name: stage.name, score: nil, passed: false, reasoning: "Error: #{message}",
      highlights: [], issues: [] }
  end

  def fail!(analysis, message)
    analysis.update!(status: 'error', error_message: message) if analysis&.persisted? || analysis&.new_record?
    analysis
  end
end
