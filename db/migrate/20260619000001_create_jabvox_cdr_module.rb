class CreateJabvoxCdrModule < ActiveRecord::Migration[7.1]
  def change
    # Super-admin toggle for the whole CDR module, mirroring the other jabvox_*_enabled_jabvox flags.
    add_column :accounts, :jabvox_cdr_enabled_jabvox, :boolean, default: false, null: false

    # An analysis pipeline: which transcription model + ordered LLM stages to run on a call.
    create_table :jabvox_cdr_pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.references :transcription_model, foreign_key: { to_table: :jabvox_ai_chat_models }, null: true
      t.boolean :is_default, default: false, null: false
      t.timestamps
    end

    # Ordered stages of a pipeline. Each runs an LLM prompt and compares its score to min_score.
    create_table :jabvox_cdr_stages do |t|
      t.references :pipeline, null: false, foreign_key: { to_table: :jabvox_cdr_pipelines }
      t.integer :position, default: 0, null: false
      t.string :name, null: false
      t.text :prompt, null: false
      t.references :llm_model, foreign_key: { to_table: :jabvox_ai_chat_models }, null: true
      t.integer :min_score, default: 0, null: false
      t.timestamps
      t.index [:pipeline_id, :position]
    end

    # Connection settings to the external PBX (Asterisk/Issabel): MySQL for CDR rows
    # and SSH/SFTP for downloading call recordings. One config per account (singleton).
    create_table :jabvox_cdr_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }

      # MySQL connection to the PBX CDR database
      t.string :mysql_host, default: '', null: false
      t.integer :mysql_port, default: 3306, null: false
      t.string :mysql_username, default: '', null: false
      t.text :mysql_password
      t.string :mysql_database, default: 'asteriskcdrdb', null: false
      t.string :mysql_table, default: 'cdr', null: false

      # SSH/SFTP access to call recordings on the PBX
      t.string :ssh_host, default: '', null: false
      t.integer :ssh_port, default: 22, null: false
      t.string :ssh_username, default: '', null: false
      t.text :ssh_password
      t.string :recordings_path, default: '/var/spool/asterisk/monitor', null: false

      # Analysis mode: manual, auto_all, auto_min_duration
      t.string :analysis_mode, default: 'manual', null: false
      t.integer :min_duration_seconds, default: 30, null: false
      t.references :default_pipeline, foreign_key: { to_table: :jabvox_cdr_pipelines }, null: true

      t.timestamps
    end

    # Result of analysing a single call, keyed by the PBX uniqueid. One per call.
    create_table :jabvox_cdr_call_analyses do |t|
      t.references :account, null: false, foreign_key: true
      t.string :uniqueid, null: false
      t.references :pipeline, foreign_key: { to_table: :jabvox_cdr_pipelines }, null: true
      t.text :transcript
      t.integer :final_score
      t.boolean :passed, default: false, null: false
      t.string :status, default: 'pending', null: false
      t.text :error_message
      t.jsonb :stages_data, default: [], null: false
      t.timestamps
      t.index [:account_id, :uniqueid], unique: true
    end

    # Which users may view CDR reports within an account. Admins always can.
    create_table :jabvox_cdr_report_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :can_view, default: false, null: false
      t.timestamps
      t.index [:account_id, :user_id], unique: true
    end

    # Optional extension -> user/label mapping for nicer report labels.
    create_table :jabvox_cdr_extension_mappings do |t|
      t.references :account, null: false, foreign_key: true
      t.string :extension, null: false
      t.references :user, foreign_key: true, null: true
      t.string :label, default: '', null: false
      t.timestamps
      t.index [:account_id, :extension], unique: true
    end
  end
end
