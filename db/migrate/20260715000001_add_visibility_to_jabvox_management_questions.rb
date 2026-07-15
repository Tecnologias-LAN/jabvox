class AddVisibilityToJabvoxManagementQuestions < ActiveRecord::Migration[7.1]
  def change
    # "Mostrar esta pregunta solo si…" — conditional visibility rules.
    # Shape: { "logic": "and"|"or", "rules": [ { "question": "<label>",
    #          "operator": "equals"|"not_equals"|"includes"|"answered", "value": "<x>" } ] }
    # Empty hash ({}) means the question is always visible. Kept as jsonb so we
    # can query/inspect rules and keep them portable through import/export.
    add_column :jabvox_management_questions, :visibility, :jsonb, default: {}, null: false
  end
end
