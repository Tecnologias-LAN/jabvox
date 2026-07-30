# CDR pipelines gain the transcription_prompt column so they mirror audio
# pipelines exactly and can be kept in sync between both modules. CDR's
# analysis service does not read it today, but storing it keeps a shared
# pipeline identical across CDR and Audio Analysis.
class AddTranscriptionPromptToCdrPipelines < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:jabvox_cdr_pipelines, :transcription_prompt)

    add_column :jabvox_cdr_pipelines, :transcription_prompt, :text
  end
end
