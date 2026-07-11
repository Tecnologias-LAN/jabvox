# Adds conditional-display support to custom columns, so a column (question) can
# be shown only when another column in the same table has a given value. This
# powers "management with questions" flows where answering a master field (e.g.
# "Tipo de acompañamiento") reveals the follow-up questions.
#
#   depends_on_jabvox : name_jabvox of the controlling column in the same table
#                       (nil = always visible).
#   show_when_jabvox  : jsonb array of controlling values that reveal this column.
#                       The column shows when the controlling answer matches ANY
#                       of them (for a multiselect master, ANY overlap counts).
class AddConditionsToJabvoxCustomColumns < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_custom_columns, :depends_on_jabvox, :string
    add_column :jabvox_custom_columns, :show_when_jabvox, :jsonb, default: [], null: false
  end
end
