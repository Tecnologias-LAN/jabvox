class CreateJabvoxClickToCallModule < ActiveRecord::Migration[7.1]
  def change
    # Toggle for the click-to-call module.
    add_column :accounts, :jabvox_click_to_call_enabled_jabvox, :boolean, default: false, null: false

    # Typification: the bridge entity between a call and an analysis pipeline.
    # Deliberately simple (name, description, active), as in the original design.
    create_table :jabvox_typifications do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description, default: '', null: false
      t.boolean :is_active, default: true, null: false
      t.timestamps
      t.index [:account_id, :name], unique: true
    end

    # Manual click-to-call log. uniqueid bridges this row to the Asterisk recording.
    create_table :jabvox_call_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :contact, foreign_key: true, null: true
      t.references :jabvox_lead, foreign_key: true, null: true
      t.references :conversation, foreign_key: true, null: true
      t.references :typification, foreign_key: { to_table: :jabvox_typifications }, null: true
      t.string :phone_number, default: '', null: false
      t.string :extension, default: '', null: false
      t.string :uniqueid
      t.string :status, default: 'calling', null: false
      t.text :note
      t.datetime :called_at
      t.timestamps
      t.index :uniqueid
    end

    # Pipelines resolve which one to use for a call via typification_id.
    add_reference :jabvox_cdr_pipelines, :typification, foreign_key: { to_table: :jabvox_typifications }, null: true
    add_reference :jabvox_audio_pipelines, :typification, foreign_key: { to_table: :jabvox_typifications }, null: true
  end
end
