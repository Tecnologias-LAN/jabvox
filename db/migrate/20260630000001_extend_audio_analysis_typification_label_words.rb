# Extends the Audio Analysis module so that:
# - a per-file typification travels into the analysis result (it used to be lost),
# - each job carries an auto-generated incremental label (analisis1, analisis2…),
# - results can store word/segment-level transcript timestamps,
# - the pipeline chooses the transcript timestamp granularity (none/word/segment).
class ExtendAudioAnalysisTypificationLabelWords < ActiveRecord::Migration[7.1]
  def change
    # Per-file typification carried into the result (mirrors assigned_agent_id).
    add_column :jabvox_audio_results, :typification_id, :bigint
    add_index :jabvox_audio_results, :typification_id
    add_foreign_key :jabvox_audio_results, :jabvox_typifications, column: :typification_id

    # Word/segment-level timestamps from transcription (verbose_json), when enabled.
    add_column :jabvox_audio_results, :transcript_words_jabvox, :jsonb, null: false, default: []

    # Auto-generated, server-side incremental analysis label (e.g. "analisis3").
    add_column :jabvox_audio_jobs, :label_jabvox, :string
    add_index :jabvox_audio_jobs, %i[account_id label_jabvox],
              name: 'index_jabvox_audio_jobs_on_account_and_label'

    # Transcript timestamp granularity: 'none' | 'word' | 'segment'.
    add_column :jabvox_audio_pipelines, :timestamp_mode_jabvox, :string, null: false, default: 'none'
    # Segment length in seconds when timestamp_mode is 'segment'.
    add_column :jabvox_audio_pipelines, :segment_seconds_jabvox, :integer, null: false, default: 30
  end
end
