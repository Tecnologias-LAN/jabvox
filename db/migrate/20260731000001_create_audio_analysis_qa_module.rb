# Rediseño del módulo de Análisis de Audio hacia un sistema de QA (Quality
# Assurance) de llamadas, independiente y configurable por cuenta. Agrega:
#
#  - Infaltables por tipificación (lo que NO puede faltar en cada tipo de llamada).
#  - Criterios de Anatomía / Cercanía (empatía, escucha, naturalidad…), evaluados
#    de forma cualitativa y contextual, aparte del score de infaltables.
#  - Asesores propios del módulo (independientes del CRM, con opción de vincular
#    a un usuario del CRM) para calificar sin depender del catálogo de usuarios.
#  - Patrones de nombre de archivo configurables, para parsear llamadas tipo
#    "3002490237-AMP Paula Ramírez.wav" y vincularlas al asesor/tipificación.
#  - Columnas de resultado QA en jabvox_audio_results (infaltables, anatomía,
#    re-tipificación detectada, resumen de hallazgos y estado de revisión).
#  - Umbral de revisión y pesos a nivel pipeline.
class CreateAudioAnalysisQaModule < ActiveRecord::Migration[7.1]
  def change
    # ── Infaltables por tipificación ──────────────────────────────────────
    # Cada tipificación define una lista de comportamientos que deben ocurrir.
    # `optional` marca los "Deseable:" del documento (no bajan el score si faltan).
    create_table :jabvox_audio_infaltables do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :typification_id, null: false
      t.text :text, null: false
      t.integer :position, null: false, default: 0
      t.boolean :optional, null: false, default: false
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :jabvox_audio_infaltables, %i[account_id typification_id],
              name: 'index_audio_infaltables_on_account_and_typification'
    add_foreign_key :jabvox_audio_infaltables, :jabvox_typifications, column: :typification_id
    add_foreign_key :jabvox_audio_infaltables, :users, column: :created_by_id

    # ── Criterios de Anatomía / Cercanía ──────────────────────────────────
    # Los 12 criterios del documento de Anatomía (empatía, escucha activa,
    # naturalidad…). Cualitativos: se reportan como buena práctica / oportunidad,
    # sin peso en el score de infaltables (recomendación del propio doc QA).
    create_table :jabvox_audio_anatomy_criteria do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.text :description, null: false, default: ''
      t.text :positive_signal, null: false, default: ''
      t.text :opportunity_signal, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id
      t.timestamps
    end
    unless index_exists?(:jabvox_audio_anatomy_criteria, :account_id)
      add_index :jabvox_audio_anatomy_criteria, :account_id,
                name: 'index_audio_anatomy_on_account'
    end
    add_foreign_key :jabvox_audio_anatomy_criteria, :users, column: :created_by_id

    # ── Asesores propios del módulo ───────────────────────────────────────
    # Un asesor puede existir solo en el módulo (nombre + external_id, p. ej. el
    # "01" del nombre de archivo) y/o vincularse a un usuario del CRM.
    create_table :jabvox_audio_advisors do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.string :external_id
      t.bigint :user_id
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id
      t.timestamps
    end
    # Unique por cuenta: es la llave del parser de nombres. Postgres permite
    # varios NULL, así que los asesores sin external_id no chocan entre sí.
    add_index :jabvox_audio_advisors, %i[account_id external_id],
              unique: true, name: 'index_audio_advisors_on_account_and_external_id'
    add_foreign_key :jabvox_audio_advisors, :users, column: :user_id
    add_foreign_key :jabvox_audio_advisors, :users, column: :created_by_id

    # ── Patrones de nombre de archivo ─────────────────────────────────────
    # Plantilla configurable para parsear el nombre del audio y extraer campos
    # (teléfono, asesor, tipificación, fecha, id de llamada). Ej.:
    #   "{phone}-{campaign} {advisor_name}"  →  "3002490237-AMP Paula Ramírez"
    #   "{advisor_id}-{typification_id}-{date}-{call_id}"  →  "01-05-2026-7890"
    create_table :jabvox_audio_filename_patterns do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.string :pattern, null: false
      t.string :date_format, null: false, default: '%d-%m-%Y'
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.bigint :created_by_id
      t.timestamps
    end
    unless index_exists?(:jabvox_audio_filename_patterns, :account_id)
      add_index :jabvox_audio_filename_patterns, :account_id,
                name: 'index_audio_filename_patterns_on_account'
    end
    add_foreign_key :jabvox_audio_filename_patterns, :users, column: :created_by_id

    # ── Extensión de resultados con el resultado de QA ────────────────────
    # infaltables_result: [{ id, text, optional, status, evidence, timestamp, confidence }]
    #   status ∈ CUMPLE | NO_CUMPLE | NO_APLICA | NO_VERIFICABLE
    add_column :jabvox_audio_results, :infaltables_result, :jsonb, null: false, default: []
    # anatomy_result: [{ id, name, status(LIKEU|OPORTUNIDAD|NO_VERIFICABLE), evidence, timestamp, confidence }]
    add_column :jabvox_audio_results, :anatomy_result, :jsonb, null: false, default: []
    # % de infaltables cumplidos sobre los aplicables (NO_APLICA excluido del denominador).
    add_column :jabvox_audio_results, :infaltables_score, :integer
    add_column :jabvox_audio_results, :infaltables_applicable, :integer
    add_column :jabvox_audio_results, :infaltables_met, :integer
    # Tipificación que la IA considera correcta (puede diferir de la asignada).
    add_column :jabvox_audio_results, :detected_typification_id, :bigint
    # Resumen: { summary, findings:[{finding, evidence, moment, opportunity, coaching}] }
    add_column :jabvox_audio_results, :qa_summary, :jsonb, null: false, default: {}
    # Estado de revisión: 'ok' | 'en_revision' (cuando el score cae bajo el umbral).
    add_column :jabvox_audio_results, :review_status, :string, null: false, default: 'ok'
    # Asesor propio del módulo (complementa assigned_agent_id, que es un User del CRM).
    add_column :jabvox_audio_results, :advisor_id, :bigint
    # Metadatos crudos extraídos del nombre de archivo por el parser.
    add_column :jabvox_audio_results, :parsed_metadata, :jsonb, null: false, default: {}
    add_index :jabvox_audio_results, :detected_typification_id
    add_index :jabvox_audio_results, :advisor_id
    add_index :jabvox_audio_results, :review_status
    add_foreign_key :jabvox_audio_results, :jabvox_typifications, column: :detected_typification_id
    add_foreign_key :jabvox_audio_results, :jabvox_audio_advisors, column: :advisor_id

    # ── Pipeline: umbral de revisión y modo QA ────────────────────────────
    # Umbral bajo el cual una llamada entra a revisión (0..100). El escalado por
    # stages (min_score) ya existe; este es el umbral de negocio del QA.
    add_column :jabvox_audio_pipelines, :review_threshold_jabvox, :integer, null: false, default: 60
    # Activa el motor de QA por infaltables (vs. el análisis genérico por stages).
    add_column :jabvox_audio_pipelines, :qa_mode_jabvox, :boolean, null: false, default: false
  end
end
