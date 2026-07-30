# frozen_string_literal: true

# Agente virtual / Voice Broadcast saliente: llama a los contactos de una campaña
# del dialer y reproduce un audio a quien contesta (AMD para no gastar audio en
# contestadores), con captura de DTMF opcional (incl. opt-out/DNC), pacing/CPS,
# reintentos y reportes. Reutiliza la lista de contactos de una JabvoxDialerCampaign
# existente; NO toca el flujo del dialer predictivo.
class CreateJabvoxVoiceBroadcastsModule < ActiveRecord::Migration[7.1]
  def change
    add_module_flag
    create_broadcasts_table
    create_recipients_table
    create_audit_table
  end

  private

  def add_module_flag
    return if column_exists?(:accounts, :jabvox_voice_broadcast_enabled_jabvox)

    add_column :accounts, :jabvox_voice_broadcast_enabled_jabvox, :boolean, default: false, null: false
  end

  def create_broadcasts_table
    return if table_exists?(:jabvox_voice_broadcasts)

    create_table :jabvox_voice_broadcasts do |t|
      t.bigint :account_id, null: false
      t.bigint :jabvox_dialer_campaign_id, null: false # lista de contactos reutilizada
      t.bigint :created_by_id
      t.string :name_jabvox, null: false, default: ''
      # draft | running | paused | completed | stopped
      t.string :status_jabvox, null: false, default: 'draft'
      # Audio ya transcodificado a WAV 8k mono; nombre base SIN extension para Playback().
      t.string :audio_filename_jabvox      # p.ej. "vb_37_12_1730000000"
      t.string :audio_original_name_jabvox # nombre original que subio el admin (display)
      t.integer :audio_duration_ms_jabvox
      t.boolean :audio_deployed_jabvox, null: false, default: false # ya copiado al PBX
      # Marcacion
      t.string :caller_id_jabvox, null: false, default: ''
      t.integer :max_concurrent_jabvox, null: false, default: 5   # canales simultaneos
      t.integer :cps_jabvox, null: false, default: 1              # llamadas por segundo (tope)
      t.integer :max_retries_jabvox, null: false, default: 0
      t.integer :retry_interval_jabvox, null: false, default: 300 # segundos (backoff base)
      # Comportamiento
      t.boolean :amd_enabled_jabvox, null: false, default: true
      t.boolean :dtmf_enabled_jabvox, null: false, default: false
      t.string :dtmf_optout_digit_jabvox, default: '9' # tecla que marca DNC/opt-out
      # Ventana horaria (misma zona que el dialer). Vacio = sin restriccion horaria.
      t.string :calling_hours_start_jabvox
      t.string :calling_hours_end_jabvox
      # Contadores materializados para el reporte/progreso sin recontar.
      t.integer :total_recipients_jabvox, null: false, default: 0
      t.integer :dialed_count_jabvox, null: false, default: 0
      t.integer :answered_human_count_jabvox, null: false, default: 0
      t.integer :answered_machine_count_jabvox, null: false, default: 0
      t.integer :played_complete_count_jabvox, null: false, default: 0
      t.integer :failed_count_jabvox, null: false, default: 0
      t.datetime :started_at_jabvox
      t.datetime :finished_at_jabvox
      t.timestamps
    end

    add_index :jabvox_voice_broadcasts, :account_id, name: 'idx_vb_account'
    add_index :jabvox_voice_broadcasts, %i[account_id status_jabvox], name: 'idx_vb_account_status'
    add_index :jabvox_voice_broadcasts, :jabvox_dialer_campaign_id, name: 'idx_vb_campaign'
  end

  def create_recipients_table
    return if table_exists?(:jabvox_voice_broadcast_recipients)

    create_table :jabvox_voice_broadcast_recipients do |t|
      t.bigint :jabvox_voice_broadcast_id, null: false
      t.bigint :account_id, null: false
      t.bigint :contact_id # CRM contact (para nombre); puede ser nil
      t.string :phone_jabvox, null: false
      t.string :name_jabvox
      # pending | calling | done | failed  (estado de MARCACION del destinatario)
      t.string :status_jabvox, null: false, default: 'pending'
      # answered_human | answered_machine | no_answer | busy | congestion | failed |
      # played_complete | hung_up_early | opted_out  (desenlace final)
      t.string :outcome_jabvox
      t.string :amd_status_jabvox # HUMAN | MACHINE | NOTSURE
      t.boolean :played_full_jabvox, null: false, default: false
      t.string :dtmf_pressed_jabvox
      t.integer :duration_ms_jabvox
      t.integer :attempts_jabvox, null: false, default: 0
      t.datetime :last_attempt_at_jabvox
      t.string :recording_file_jabvox
      t.string :uniqueid_jabvox   # uniqueid de Asterisk (correlacion + CDR)
      t.string :linkedid_jabvox
      t.timestamps
    end

    add_index :jabvox_voice_broadcast_recipients, :jabvox_voice_broadcast_id, name: 'idx_vbr_broadcast'
    add_index :jabvox_voice_broadcast_recipients, %i[jabvox_voice_broadcast_id status_jabvox],
              name: 'idx_vbr_broadcast_status'
    add_index :jabvox_voice_broadcast_recipients, :account_id, name: 'idx_vbr_account'
    # Correlacion rapida por uniqueid al recibir eventos AMI.
    add_index :jabvox_voice_broadcast_recipients, %i[account_id uniqueid_jabvox],
              name: 'idx_vbr_account_uniqueid', where: 'uniqueid_jabvox IS NOT NULL'
    # Un contacto no puede estar duplicado dentro del mismo broadcast.
    add_index :jabvox_voice_broadcast_recipients, %i[jabvox_voice_broadcast_id phone_jabvox],
              unique: true, name: 'idx_vbr_unique_phone'
  end

  # Auditoria de acciones sensibles: quien lanzo/pauso/detuvo/subio audio, cuando.
  def create_audit_table
    return if table_exists?(:jabvox_voice_broadcast_audits)

    create_table :jabvox_voice_broadcast_audits do |t|
      t.bigint :jabvox_voice_broadcast_id, null: false
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.string :action_jabvox, null: false # created | audio_uploaded | started | paused | resumed | stopped
      t.jsonb :metadata_jabvox, null: false, default: {}
      t.timestamps
    end

    add_index :jabvox_voice_broadcast_audits, :jabvox_voice_broadcast_id, name: 'idx_vba_broadcast'
    add_index :jabvox_voice_broadcast_audits, %i[account_id created_at], name: 'idx_vba_account_time'
  end
end
