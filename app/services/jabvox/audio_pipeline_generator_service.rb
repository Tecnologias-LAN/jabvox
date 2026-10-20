# Crea/actualiza un pipeline de QA por cada tipificación que tenga infaltables,
# siguiendo el modelo "una tipificación = un pipeline". Cada pipeline queda con
# DOS etapas de validación:
#   1. 1ª Validación  — evalúa la llamada contra los infaltables.
#   2. 2ª Validación (auditoría) — solo corre si la 1ª cae bajo el umbral; revisa
#      el resultado de la 1ª, puede corregirlo y explica el porqué del porcentaje.
#
# Es idempotente: re-ejecutar no duplica pipelines ni etapas.
class Jabvox::AudioPipelineGeneratorService
  # rubocop:disable Metrics/ParameterLists
  def initialize(account, transcription_model:, validation_model:, audit_model: nil, threshold: 60, created_by: nil)
    @account = account
    @transcription_model = transcription_model
    @validation_model = validation_model
    @audit_model = audit_model || validation_model
    @threshold = threshold
    @created_by = created_by
  end
  # rubocop:enable Metrics/ParameterLists

  # Genera un pipeline por cada tipificación con infaltables activos. Devuelve el
  # número de pipelines creados/actualizados.
  def generate_all
    typifications = @account.jabvox_typifications
                            .joins(:audio_infaltables)
                            .where(jabvox_audio_infaltables: { active: true })
                            .distinct
    typifications.sum { |t| generate_for(t) ? 1 : 0 }
  end

  # Crea/actualiza el pipeline de UNA tipificación. Devuelve el pipeline.
  def generate_for(typification)
    pipeline = @account.jabvox_audio_pipelines.find_or_initialize_by(typification_id: typification.id)
    pipeline.assign_attributes(
      name: "QA - #{typification.name}".first(150),
      typification: typification,
      qa_mode_jabvox: true,
      # Respetar la tipificación del mapeo del nombre; no recalificar en otra.
      qa_reclassify_jabvox: false,
      review_threshold_jabvox: @threshold,
      transcription_model: @transcription_model,
      # whisper-1 permite timestamps por palabra; por eso 'segment'.
      timestamp_mode_jabvox: 'segment',
      segment_seconds_jabvox: 30
    )
    pipeline.created_by_id ||= @created_by&.id
    pipeline.save!
    sync_stages!(pipeline)
    pipeline
  end

  private

  # Deja exactamente 2 etapas: Validación y Auditoría, con su modelo y umbral.
  def sync_stages!(pipeline)
    stages = pipeline.stages.ordered.to_a
    upsert_stage(pipeline, stages[0], position: 0, name: '1ª Validación',
                                      model: @validation_model,
                                      prompt: 'Evalúa la llamada contra los infaltables de la tipificación.')
    upsert_stage(pipeline, stages[1], position: 1, name: '2ª Validación (auditoría)',
                                      model: @audit_model,
                                      prompt: 'Audita el resultado de la 1ª validación cuando queda bajo el umbral.')
    # Elimina etapas sobrantes de pipelines viejos (más de 2).
    pipeline.stages.where.not(position: [0, 1]).destroy_all
  end

  # rubocop:disable Metrics/ParameterLists
  def upsert_stage(pipeline, stage, position:, name:, model:, prompt:)
    stage ||= pipeline.stages.build
    stage.assign_attributes(position: position, name: name, min_score: @threshold,
                            llm_model: model, prompt: prompt)
    stage.save!
  end
  # rubocop:enable Metrics/ParameterLists
end
