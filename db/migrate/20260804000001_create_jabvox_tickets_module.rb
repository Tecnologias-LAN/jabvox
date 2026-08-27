class CreateJabvoxTicketsModule < ActiveRecord::Migration[7.1]
  def change
    add_module_flag
    create_helpdesk_config_table
    create_categories_table
    create_tickets_table
    create_comments_table
    create_activities_table
  end

  private

  # Flag por cuenta: habilita que los usuarios de la cuenta registren tickets.
  def add_module_flag
    return if column_exists?(:accounts, :jabvox_tickets_enabled_jabvox)

    add_column :accounts, :jabvox_tickets_enabled_jabvox, :boolean, default: false, null: false
  end

  # Config global del helpdesk central: qué cuenta es la gestora y cómo autoasigna.
  def create_helpdesk_config_table
    return if table_exists?(:jabvox_ticket_helpdesk_configs)

    create_table :jabvox_ticket_helpdesk_configs do |t|
      t.integer :account_id, null: false # cuenta gestora (staff = admins; resolvers = agentes)
      t.integer :auto_assign_mode_jabvox, null: false, default: 0 # 0 manual, 1 round_robin, 2 by_category
      t.boolean :active_jabvox, null: false, default: true
      t.jsonb :settings_jabvox, null: false, default: {}
      t.timestamps
    end

    add_index :jabvox_ticket_helpdesk_configs, :account_id, unique: true, name: 'idx_ticket_helpdesk_account'
  end

  def create_categories_table
    return if table_exists?(:jabvox_ticket_categories)

    create_table :jabvox_ticket_categories do |t|
      t.integer :account_id, null: false
      t.integer :responsible_id # agente responsable para autoasignación por categoría
      t.string :name_jabvox, null: false
      t.integer :category_type_jabvox, null: false, default: 0 # 0 incidente, 1 requerimiento, 2 solicitud
      t.string :color_jabvox, null: false, default: '#1F93FF'
      t.text :description_jabvox
      t.integer :sla_response_minutes_jabvox, null: false, default: 60
      t.integer :sla_resolution_minutes_jabvox, null: false, default: 1440
      t.integer :position_jabvox, null: false, default: 0
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_ticket_categories, :account_id, name: 'idx_ticket_categories_account'
    add_index :jabvox_ticket_categories, [:account_id, :active_jabvox], name: 'idx_ticket_categories_account_active'
  end

  def create_tickets_table
    return if table_exists?(:jabvox_tickets)

    create_table :jabvox_tickets do |t|
      t.integer :account_id, null: false
      t.integer :display_id_jabvox, null: false # secuencial por cuenta
      t.string :title_jabvox, null: false
      t.text :description_jabvox
      t.integer :ticket_category_id
      t.integer :category_type_jabvox, null: false, default: 0 # denormalizado
      t.integer :priority_jabvox, null: false, default: 1 # 0 baja,1 media,2 alta,3 urgente
      t.integer :status_jabvox, null: false, default: 0 # 0 nuevo..6 reabierto (ver modelo)
      t.integer :requester_id, null: false
      t.integer :assignee_id
      t.integer :conversation_id
      t.integer :contact_id
      t.datetime :due_at_jabvox
      t.datetime :first_response_at_jabvox
      t.datetime :resolved_at_jabvox
      t.datetime :closed_at_jabvox
      t.text :resolution_jabvox
      t.integer :resolution_type_jabvox # 0 solucionado,1 duplicado,2 no_procede
      t.integer :satisfaction_rating_jabvox
      t.text :satisfaction_comment_jabvox
      t.integer :reopened_count_jabvox, null: false, default: 0
      t.jsonb :custom_attributes_jabvox, null: false, default: {}
      t.timestamps
    end

    add_index :jabvox_tickets, [:account_id, :display_id_jabvox], unique: true, name: 'idx_tickets_account_display'
    add_index :jabvox_tickets, [:account_id, :status_jabvox], name: 'idx_tickets_account_status'
    add_index :jabvox_tickets, [:account_id, :requester_id], name: 'idx_tickets_account_requester'
    add_index :jabvox_tickets, [:account_id, :assignee_id], name: 'idx_tickets_account_assignee'
    add_index :jabvox_tickets, [:account_id, :category_type_jabvox], name: 'idx_tickets_account_ctype'
  end

  def create_comments_table
    return if table_exists?(:jabvox_ticket_comments)

    create_table :jabvox_ticket_comments do |t|
      t.integer :ticket_id, null: false
      t.integer :user_id, null: false
      t.text :body_jabvox, null: false
      t.boolean :private_jabvox, null: false, default: false # nota interna: no se notifica al solicitante
      t.timestamps
    end

    add_index :jabvox_ticket_comments, :ticket_id, name: 'idx_ticket_comments_ticket'
  end

  def create_activities_table
    return if table_exists?(:jabvox_ticket_activities)

    create_table :jabvox_ticket_activities do |t|
      t.integer :ticket_id, null: false
      t.integer :user_id
      t.string :action_jabvox, null: false
      t.string :from_value_jabvox
      t.string :to_value_jabvox
      t.jsonb :metadata_jabvox, null: false, default: {}
      t.timestamps
    end

    add_index :jabvox_ticket_activities, :ticket_id, name: 'idx_ticket_activities_ticket'
  end
end
