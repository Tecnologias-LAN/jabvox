require 'openai'

# Analyzes a single audio file for a result row: download -> transcribe (Whisper)
# -> run pipeline stages with escalation logic -> persist score/passed/sentiment.
# rubocop:disable Metrics/ClassLength
class Jabvox::AudioAnalysisService
  TRANSCRIBE_TIMEOUT = 120
  STAGE_TIMEOUT = 60
  MAX_AUDIO_BYTES = 25 * 1024 * 1024

  def initialize(result)
    @result = result
    @job = result.job
    @account = result.account
    @pipeline = @job.pipeline
    @storage = @job.storage
  end

  # rubocop:disable Metrics/MethodLength
  def call
    started = monotonic_ms
    @result.update!(status: 'processing')

    return fail!('Pipeline o almacenamiento no disponible') unless @pipeline && @storage

    transcript, words = transcribe
    return fail!('No se pudo transcribir el audio') if transcript.blank?

    if @pipeline.qa_mode_jabvox
      evaluate_qa(transcript, words, started)
    else
      stages_data, final = evaluate_stages(transcript)
      @result.update!(
        transcript: transcript,
        transcript_words_jabvox: words || [],
        stages_data: stages_data,
        final_score: final[:score],
        passed: final[:passed],
        sentiment: final[:sentiment],
        status: 'completed',
        processing_time_ms: monotonic_ms - started,
        error_message: nil
      )
    end
  rescue StandardError => e
    Rails.logger.error "[AudioAnalysis] #{@result.file_key} failed: #{e.message}"
    fail!(e.message)
  ensure
    @job.refresh_progress!
  end
  # rubocop:enable Metrics/MethodLength

  private

  # Modo QA: evalúa la transcripción por infaltables + anatomía de la tipificación
  # resuelta para este result, calcula el % de cumplimiento y marca 'en_revision'
  # cuando cae bajo el umbral del pipeline. Todo queda persistido en el result.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def evaluate_qa(transcript, words, started)
    typification = @result.typification || @pipeline.typification
    evaluation = Jabvox::AudioQaEvaluatorService.new(
      account: @account, pipeline: @pipeline, typification: typification, transcript: transcript
    ).call

    detected = resolve_detected_typification(evaluation.detected_typification_name)
    retypification_reason = evaluation.detected_typification_reason

    # Re-tipificación (OPT-IN, por defecto desactivada): cuando la tipificación
    # viene de un mapeo explícito del nombre de archivo, se respeta y NO se
    # recalifica — la IA solo deja una NOTA (retypification_reason) si cree que es
    # otra. Reasignar automáticamente inflaba los scores (la IA elegía la
    # tipificación más fácil de cumplir). Solo recalifica si el pipeline lo activa.
    if @pipeline.qa_reclassify_jabvox && detected && detected.id != typification&.id &&
       detected.audio_infaltables.active.exists?
      typification = detected
      evaluation = Jabvox::AudioQaEvaluatorService.new(
        account: @account, pipeline: @pipeline, typification: detected, transcript: transcript
      ).call
      detected = resolve_detected_typification(evaluation.detected_typification_name) || detected
      retypification_reason = evaluation.detected_typification_reason.presence || retypification_reason
    end

    threshold = @pipeline.review_threshold_jabvox.to_i
    first_pass_score = evaluation.score

    # Segunda validación: si la primera cae bajo el umbral, un auditor revisa el
    # resultado de la primera, puede corregirlo y explica el porqué del porcentaje.
    review_explanation = nil
    if first_pass_score.present? && first_pass_score < threshold
      evaluation = Jabvox::AudioQaEvaluatorService.new(
        account: @account, pipeline: @pipeline, typification: typification, transcript: transcript
      ).audit(evaluation)
      review_explanation = evaluation.review_explanation
    end

    review = evaluation.score.present? && evaluation.score < threshold ? 'en_revision' : 'ok'
    passed = evaluation.score.present? && evaluation.score >= threshold

    @result.update!(
      transcript: transcript,
      transcript_words_jabvox: words || [],
      # Tipificación con la que REALMENTE se calificó (puede ser la re-tipificada).
      typification_id: typification&.id,
      infaltables_result: evaluation.infaltables,
      anatomy_result: evaluation.anatomy,
      # infaltables_score = % puro de infaltables; final_score = global ponderado.
      infaltables_score: evaluation.infaltables_score,
      infaltables_applicable: evaluation.applicable,
      infaltables_met: evaluation.met,
      final_score: evaluation.score,
      first_pass_score: first_pass_score,
      passed: passed,
      sentiment: evaluation.sentiment,
      detected_typification_id: detected&.id,
      retypification_reason: retypification_reason,
      review_explanation: review_explanation,
      qa_summary: evaluation.summary,
      review_status: review,
      status: 'completed',
      processing_time_ms: monotonic_ms - started,
      error_message: nil
    )
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def resolve_detected_typification(name)
    return nil if name.blank?

    @account.jabvox_typifications.where('LOWER(name) = ?', name.downcase).first
  end

  # Returns [transcript_text, words_array]. words_array is [] unless the pipeline
  # requests timestamps; for 'word' it is per-word, for 'segment' it is per-segment
  # of segment_seconds_jabvox (built from word timings).
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def transcribe
    tmp = nil
    pcm = nil
    model = @pipeline.transcription_model || @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    return [nil, nil] unless model

    tmp = Jabvox::AudioBucketService.new(@storage).download(@result.file_key)
    return [nil, nil] unless tmp
    return [nil, nil] if tmp.size > MAX_AUDIO_BYTES

    # Las grabaciones de telefonía suelen venir en WAV GSM 8kHz. Whisper
    # malinterpreta ese codec (devuelve "INTERRUPCIÓN..." o texto basura), así que
    # se normaliza con ffmpeg a MP3 16kHz mono antes de transcribir. Se usa MP3 (no
    # PCM) porque PCM16 de una llamada larga infla a decenas de MB y el endpoint
    # responde 413; MP3 48k mantiene el archivo liviano y whisper lo acepta igual.
    # Si ffmpeg no está o falla, se usa el archivo original tal cual.
    pcm = convert_to_mp3(tmp)
    audio_file = pcm || tmp

    mode = @pipeline.timestamp_mode_jabvox
    # Usa el modelo de transcripción configurado (whisper-1, gpt-4o-transcribe,
    # gpt-4o-mini-transcribe, etc.); cae a whisper-1 si no viene nombre.
    transcribe_model = model.model_jabvox.presence || 'whisper-1'
    params = { model: transcribe_model, file: audio_file, language: 'es' }
    params[:prompt] = @pipeline.transcription_prompt if @pipeline.transcription_prompt.present?

    # Los timestamps por palabra (verbose_json + timestamp_granularities) solo los
    # soporta whisper-1; los modelos gpt-4o*-transcribe los rechazan. Para esos,
    # se transcribe el texto sin timestamps aunque el pipeline los pida.
    supports_word_timestamps = transcribe_model.include?('whisper')
    if mode == 'none' || !supports_word_timestamps
      text = openai_client(model, TRANSCRIBE_TIMEOUT).audio.transcribe(parameters: params)['text'].presence
      return [text, []]
    end

    # verbose_json + word granularity gives per-word start/end times.
    # NOTE: in multipart/form-data the param must be sent as the repeated key
    # "timestamp_granularities[]"; ruby-openai does not expand a Ruby array into
    # repeated multipart fields, so OpenAI would silently drop a plain array and
    # return no `words`. Passing the bracketed key with a string value works.
    params[:response_format] = 'verbose_json'
    params[:'timestamp_granularities[]'] = 'word'
    resp = openai_client(model, TRANSCRIBE_TIMEOUT).audio.transcribe(parameters: params)
    text = resp['text'].presence
    word_list = Array(resp['words']).map do |w|
      { 'word' => w['word'], 'start' => w['start'], 'end' => w['end'] }
    end
    # Fallback: if the API returned segments instead of words (older models or
    # when word timing is unavailable), use those so the user still sees timing.
    if word_list.empty?
      word_list = Array(resp['segments']).map do |s|
        { 'word' => s['text'].to_s.strip, 'start' => s['start'], 'end' => s['end'] }
      end
    end
    words = mode == 'segment' ? group_into_segments(word_list) : word_list
    [text, words]
  ensure
    tmp&.close!
    pcm&.close
    pcm&.unlink
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Normaliza el audio a MP3 16kHz mono 48kbps con ffmpeg. Devuelve un Tempfile
  # (el llamador lo cierra/borra en el ensure) o nil si ffmpeg no está, falla o
  # produce un archivo vacío — en cuyo caso se transcribe el original.
  def convert_to_mp3(source)
    out = Tempfile.new(['audio_norm', '.mp3'])
    out.binmode
    out.close
    ok = system('ffmpeg', '-y', '-i', source.path, '-ar', '16000', '-ac', '1',
                '-c:a', 'libmp3lame', '-b:a', '48k', out.path,
                out: File::NULL, err: File::NULL)
    if ok && File.size?(out.path)
      out.open
      out.binmode
      return out
    end
    out.unlink
    nil
  rescue StandardError => e
    Rails.logger.warn "[AudioAnalysis] ffmpeg convert failed: #{e.message}"
    out&.close
    out&.unlink
    nil
  end

  # Buckets per-word timings into fixed segments of segment_seconds_jabvox seconds,
  # concatenating the words that fall in each bucket.
  def group_into_segments(word_list)
    span = @pipeline.segment_seconds_jabvox.to_i
    span = 30 if span <= 0
    word_list.group_by { |w| (w['start'].to_f / span).floor }
             .map do |bucket, words|
               { 'start' => bucket * span, 'end' => (bucket + 1) * span,
                 'word' => words.map { |w| w['word'] }.join(' ').strip }
             end
  end

  # Escalation: if a non-last stage scores below its min_score, mark it escalated and
  # move on; if it passes, stop. Final score/passed/sentiment are from the last evaluated stage.
  def evaluate_stages(transcript)
    stages = @pipeline.stages.to_a
    stages_data = []
    last_eval = { score: nil, passed: false, sentiment: nil }

    stages.each_with_index do |stage, index|
      parsed = run_stage(stage, transcript)
      score = parsed['score'].to_i
      passed = parsed.key?('passed') ? !!parsed['passed'] : score >= stage.min_score
      is_last = index == stages.length - 1
      escalated = !is_last && score < stage.min_score

      stages_data << {
        stage_id: stage.id, name: stage.name, score: score, min_score: stage.min_score,
        passed: passed, escalated: escalated, reasoning: parsed['reasoning'].to_s,
        highlights: Array(parsed['highlights']), issues: Array(parsed['issues']),
        sentiment: parsed['sentiment']
      }
      last_eval = { score: score, passed: passed, sentiment: normalize_sentiment(parsed['sentiment']) }

      break unless escalated
    end

    [stages_data, last_eval]
  end

  def run_stage(stage, transcript)
    model = stage.llm_model || @pipeline.transcription_model ||
            @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    raise 'Sin modelo LLM configurado' unless model

    response = openai_client(model, STAGE_TIMEOUT).chat(
      parameters: {
        model: model.model_jabvox,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system_prompt(stage.prompt) },
          { role: 'user', content: transcript }
        ]
      }
    )
    JSON.parse(response.dig('choices', 0, 'message', 'content').to_s)
  end

  def system_prompt(stage_prompt)
    "#{stage_prompt}\n\n" \
      'Responde SOLO con un objeto JSON con las claves: "passed" (boolean), ' \
      '"score" (entero 0-100), "reasoning" (string), "highlights" (array de strings), ' \
      '"issues" (array de strings), "sentiment" ("positive" | "neutral" | "negative").'
  end

  def normalize_sentiment(value)
    v = value.to_s.downcase
    JabvoxAudioResult::SENTIMENTS.include?(v) ? v : nil
  end

  def openai_client(model, timeout)
    options = { access_token: model.api_key_jabvox.to_s, request_timeout: timeout }
    base = model.base_url_jabvox.presence
    options[:uri_base] = base if base
    OpenAI::Client.new(**options)
  end

  def fail!(message)
    @result.update!(status: 'error', error_message: message)
    @result
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
# rubocop:enable Metrics/ClassLength
