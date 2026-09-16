class CreateJabvoxWhatsappFlowAnswers < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_flow_answers do |t|
      t.references :jabvox_whatsapp_flow_submission, null: false, foreign_key: true,
                                                     index: { name: 'idx_jabvox_wa_flow_answers_on_submission_id' }
      t.string :screen_id, null: false
      t.string :component_id, null: false
      t.string :component_name, null: false
      t.string :component_type, null: false
      t.text :value_text
      t.timestamps
    end

    add_index :jabvox_whatsapp_flow_answers, :component_name
  end
end
