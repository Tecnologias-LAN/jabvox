class CreateJabvoxResponseBotSeats < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_response_bot_seats do |t|
      t.string :name_jabvox, null: false
      t.text :prompt_jabvox
      t.boolean :active_jabvox, default: true, null: false
      t.timestamps
    end
  end
end
