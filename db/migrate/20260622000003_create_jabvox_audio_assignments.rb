class CreateJabvoxAudioAssignments < ActiveRecord::Migration[7.1]
  def change
    # Manual typification/agent assignment for an audio file, independent of any
    # analysis job. Lets agents pre-tag audios in the browser before analyzing.
    create_table :jabvox_audio_assignments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :storage, null: false, foreign_key: { to_table: :jabvox_audio_storages }
      t.string :file_key, null: false
      t.references :typification, foreign_key: { to_table: :jabvox_typifications }, null: true
      t.references :agent, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:storage_id, :file_key], unique: true
    end
  end
end
