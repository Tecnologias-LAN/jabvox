class AddLeadFieldToJabvoxManagementQuestions < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_management_questions, bulk: true do |t|
      # "Autocompletar desde el lead" — namespaced key of the lead/contact field
      # whose value pre-fills this question at typification time. Empty = no map.
      # Examples: "contact.phone_number", "contact.custom.<key>",
      #           "contact.additional.<key>", "lead.<column>", "lead.lead_number".
      t.string :lead_field, default: '', null: false
      # When true the pre-filled value is read-only (e.g. auto Ciclo); when false
      # it is pre-filled but the agent can edit it.
      t.boolean :lead_field_locked, default: false, null: false
    end
  end
end
