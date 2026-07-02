# Brings the CDR module to parity with audio-analysis:
# - the pipeline chooses transcript timestamp granularity (none/word/segment),
# - the call analysis can store word/segment timestamps and the recording file
#   name (so the report can stream it back on demand).
class ExtendCdrTimestampsAndRecording < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_cdr_pipelines, :timestamp_mode_jabvox, :string, null: false, default: 'none'
    add_column :jabvox_cdr_pipelines, :segment_seconds_jabvox, :integer, null: false, default: 30

    add_column :jabvox_cdr_call_analyses, :transcript_words_jabvox, :jsonb, null: false, default: []
    # The PBX recording file name resolved at analysis time; used to stream playback.
    add_column :jabvox_cdr_call_analyses, :recording_file_jabvox, :string
  end
end
