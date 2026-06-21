class CreateJabvoxAudioAnalysisModule < ActiveRecord::Migration[7.1]
  def change
    # Super-admin toggle for the whole Audio Analysis module.
    add_column :accounts, :jabvox_audio_analysis_enabled_jabvox, :boolean, default: false, null: false

    # S3/MinIO storage where the audio files live. secret_access_key is encrypted.
    # use_documents_config reuses the AI-chat (Documentos) bucket config instead.
    create_table :jabvox_audio_storages do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :use_documents_config, default: false, null: false
      t.string :bucket_name, default: '', null: false
      t.string :bucket_region, default: 'us-east-1', null: false
      t.string :endpoint, default: '', null: false
      t.string :access_key, default: '', null: false
      t.text :secret_key
      t.string :path_prefix, default: '', null: false
      t.timestamps
    end

    # Analysis pipeline: transcription model + transcription prompt + ordered LLM stages.
    create_table :jabvox_audio_pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.references :transcription_model, foreign_key: { to_table: :jabvox_ai_chat_models }, null: true
      t.text :transcription_prompt
      t.boolean :is_default, default: false, null: false
      t.timestamps
    end

    create_table :jabvox_audio_stages do |t|
      t.references :pipeline, null: false, foreign_key: { to_table: :jabvox_audio_pipelines }
      t.integer :position, default: 0, null: false
      t.string :name, null: false
      t.text :prompt, null: false
      t.references :llm_model, foreign_key: { to_table: :jabvox_ai_chat_models }, null: true
      t.integer :min_score, default: 60, null: false
      t.timestamps
      t.index [:pipeline_id, :position]
    end

    # A batch job over a set of file keys. Counters are updated as files finish.
    create_table :jabvox_audio_jobs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, foreign_key: { to_table: :jabvox_audio_pipelines }, null: true
      t.references :storage, foreign_key: { to_table: :jabvox_audio_storages }, null: true
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.string :status, default: 'pending', null: false
      t.integer :total_count, default: 0, null: false
      t.integer :processed_count, default: 0, null: false
      t.integer :passed_count, default: 0, null: false
      t.integer :failed_count, default: 0, null: false
      t.integer :error_count, default: 0, null: false
      t.integer :positive_count, default: 0, null: false
      t.integer :neutral_count, default: 0, null: false
      t.integer :negative_count, default: 0, null: false
      t.integer :average_score
      t.timestamps
    end

    # One result per file in a job.
    create_table :jabvox_audio_results do |t|
      t.references :job, null: false, foreign_key: { to_table: :jabvox_audio_jobs }
      t.references :account, null: false, foreign_key: true
      t.string :file_key, null: false
      t.text :transcript
      t.integer :final_score
      t.boolean :passed, default: false, null: false
      t.string :sentiment
      t.string :status, default: 'pending', null: false
      t.text :error_message
      t.jsonb :stages_data, default: [], null: false
      t.integer :processing_time_ms
      t.timestamps
      t.index [:job_id, :file_key]
    end

    # Two-level access: can use the module + can view reports. Admins always can.
    create_table :jabvox_audio_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :can_access, default: false, null: false
      t.boolean :can_view_reports, default: false, null: false
      t.timestamps
      t.index [:account_id, :user_id], unique: true
    end
  end
end
