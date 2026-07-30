class ChangeCaptainAssistantDescriptionToText < ActiveRecord::Migration[7.0]
  def up
    column = columns(:captain_assistants).find { |c| c.name == 'description' }
    return if column&.type == :text

    change_column :captain_assistants, :description, :text
  end

  def down
    change_column :captain_assistants, :description, :string
  end
end
