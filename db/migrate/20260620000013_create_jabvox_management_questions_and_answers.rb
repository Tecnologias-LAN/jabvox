class CreateJabvoxManagementQuestionsAndAnswers < ActiveRecord::Migration[7.1]
  def change
    # Note behaviour per management state: required | optional | hidden.
    add_column :jabvox_management_states, :note_mode, :string, default: 'optional', null: false

    # Dynamic questions the admin configures per management state.
    create_table :jabvox_management_questions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_management_state, null: false, foreign_key: true
      t.string :label, null: false
      t.string :question_type, default: 'text', null: false
      t.jsonb :options, default: [], null: false
      t.boolean :required, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
      t.index [:jabvox_management_state_id, :position]
    end

    # Normalized agent answers (also embedded in Message/Note content_attributes).
    # Snapshots label/type/value so reports survive question edits/deletes.
    create_table :jabvox_management_answers do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_management_state, foreign_key: true, null: true
      t.references :jabvox_management_question, foreign_key: { on_delete: :nullify }, null: true
      t.references :message, foreign_key: true, null: true
      t.references :note, foreign_key: true, null: true
      t.string :label, default: '', null: false
      t.string :value_type, default: 'text', null: false
      t.text :value
      t.timestamps
    end
  end
end
