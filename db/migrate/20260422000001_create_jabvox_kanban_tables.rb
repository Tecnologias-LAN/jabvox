class CreateJabvoxKanbanTables < ActiveRecord::Migration[7.0]
  def change
    create_jabvox_kanban_funnels
    create_jabvox_kanban_funnel_inboxes
    create_jabvox_kanban_stages
    create_jabvox_kanban_conversation_stages
  end

  private

  def create_jabvox_kanban_funnels
    create_table :jabvox_kanban_funnels do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.integer :position_jabvox, null: false, default: 0
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_kanban_funnels, :account_id
    add_index :jabvox_kanban_funnels, [:account_id, :name_jabvox], unique: true
    add_foreign_key :jabvox_kanban_funnels, :accounts
  end

  def create_jabvox_kanban_funnel_inboxes
    create_table :jabvox_kanban_funnel_inboxes do |t|
      t.bigint :jabvox_kanban_funnel_id, null: false
      t.bigint :inbox_id, null: false
      t.timestamps
    end

    add_index :jabvox_kanban_funnel_inboxes, :jabvox_kanban_funnel_id
    add_index :jabvox_kanban_funnel_inboxes, :inbox_id
    add_index :jabvox_kanban_funnel_inboxes, [:jabvox_kanban_funnel_id, :inbox_id], unique: true, name: 'index_jabvox_funnel_inboxes_unique'
    add_foreign_key :jabvox_kanban_funnel_inboxes, :jabvox_kanban_funnels
    add_foreign_key :jabvox_kanban_funnel_inboxes, :inboxes
  end

  def create_jabvox_kanban_stages
    create_table :jabvox_kanban_stages do |t|
      t.bigint :jabvox_kanban_funnel_id, null: false
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.integer :position_jabvox, null: false, default: 0
      t.string :color_jabvox, null: false, default: '#6B7280'
      t.timestamps
    end

    add_index :jabvox_kanban_stages, :jabvox_kanban_funnel_id
    add_index :jabvox_kanban_stages, :account_id
    add_index :jabvox_kanban_stages, [:jabvox_kanban_funnel_id, :position_jabvox], name: 'index_jabvox_stages_funnel_position'
    add_foreign_key :jabvox_kanban_stages, :jabvox_kanban_funnels
    add_foreign_key :jabvox_kanban_stages, :accounts
  end

  def create_jabvox_kanban_conversation_stages
    create_table :jabvox_kanban_conversation_stages do |t|
      t.bigint :conversation_id, null: false
      t.bigint :jabvox_kanban_funnel_id, null: false
      t.bigint :jabvox_kanban_stage_id, null: false
      t.bigint :account_id, null: false
      t.bigint :moved_by_id
      t.timestamps
    end

    add_index :jabvox_kanban_conversation_stages, :account_id,
              name: 'index_jabvox_conv_stages_account'
    add_index :jabvox_kanban_conversation_stages, :jabvox_kanban_stage_id,
              name: 'index_jabvox_conv_stages_stage'
    add_index :jabvox_kanban_conversation_stages, :jabvox_kanban_funnel_id,
              name: 'index_jabvox_conv_stages_funnel'
    add_index :jabvox_kanban_conversation_stages, [:conversation_id, :jabvox_kanban_funnel_id],
              unique: true, name: 'index_jabvox_conv_stages_unique'
    add_foreign_key :jabvox_kanban_conversation_stages, :conversations
    add_foreign_key :jabvox_kanban_conversation_stages, :jabvox_kanban_funnels
    add_foreign_key :jabvox_kanban_conversation_stages, :jabvox_kanban_stages
    add_foreign_key :jabvox_kanban_conversation_stages, :accounts
  end
end
