require 'openai'

# Analyzes a single audio file for a result row: download -> transcribe (Whisper)
# -> run pipeline stages with escalation logic -> persist score/passed/sentiment.
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

  def call
    started = monotonic_ms
    @result.update!(status: 'processing')

    return fail!('Pipeline o almacenamiento no disponible') unless @pipeline && @storage

    transcript = transcribe
    return fail!('No se pudo transcribir el audio') if transcript.blank?

    stages_data, final = evaluate_stages(transcript)
    @result.update!(
      transcript: transcript,
      stages_data: stages_data,
      final_score: final[:score],
      passed: final[:passed],
      sentiment: final[:sentiment],
      status: 'completed',
      processing_time_ms: monotonic_ms - started,
      error_message: nil
    )
  rescue StandardError => e
    Rails.logger.error "[AudioAnalysis] #{@result.file_key} failed: #{e.message}"
    fail!(e.message)
  ensure
    @job.refresh_progress!
  end

  private

  def transcribe
    model = @pipeline.transcription_model || @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    return nil unless model

    tmp = Jabvox::AudioBucketService.new(@storage).download(@result.file_key)
    return nil unless tmp
    return nil if tmp.size > MAX_AUDIO_BYTES

    params = { model: 'whisper-1', file: tmp, language: 'es' }
    params[:prompt] = @pipeline.transcription_prompt if @pipeline.transcription_prompt.present?
    openai_client(model, TRANSCRIBE_TIMEOUT).audio.transcribe(parameters: params)['text'].presence
  ensure
    tmp&.close!
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
