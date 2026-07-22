class AddQuestionKeyAndCreatedByToManagement < ActiveRecord::Migration[7.1]
  # Two additions for external-CRM mapping:
  #
  # 1) question_key on jabvox_management_questions: a STABLE key for "the same
  #    logical question" across every management state. Today each state owns its
  #    own copy of a question (e.g. "¿Gestionado?" exists 41 times with 41 ids),
  #    so there is no way to map "this question" to a single CRM field. question_key
  #    is derived from the label (slug) and is identical for the same question in
  #    all states, so the CRM maps once per key instead of per id.
  #
  # 2) created_by_id on jabvox_management_states and jabvox_typifications: the user
  #    who created the catalog entry. Additive + nullable, so existing rows stay
  #    valid (they were created before this was tracked).
  def up
    add_column :jabvox_management_questions, :question_key, :string
    add_index  :jabvox_management_questions, %i[account_id question_key],
               name: 'idx_mgmt_questions_account_question_key'

    add_reference :jabvox_management_states, :created_by,
                  foreign_key: { to_table: :users }, null: true
    add_reference :jabvox_typifications, :created_by,
                  foreign_key: { to_table: :users }, null: true

    backfill_question_keys
  end

  def down
    remove_reference :jabvox_typifications, :created_by, foreign_key: { to_table: :users }
    remove_reference :jabvox_management_states, :created_by, foreign_key: { to_table: :users }
    remove_index :jabvox_management_questions, name: 'idx_mgmt_questions_account_question_key'
    remove_column :jabvox_management_questions, :question_key
  end

  private

  # Fill question_key for every existing question from its label, so the stable
  # key exists retroactively. Done in raw SQL to avoid model callbacks/validations
  # on a possibly-large table; mirrors JabvoxManagementQuestion.slugify_label.
  def backfill_question_keys
    JabvoxManagementQuestion.reset_column_information
    JabvoxManagementQuestion.where(question_key: nil).find_each(batch_size: 500) do |q|
      key = JabvoxManagementQuestion.slugify_label(q.label) || 'campo'
      q.update_columns(question_key: key) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
