class CreateJabvoxAnalyticsModule < ActiveRecord::Migration[7.1]
  def change
    # Super-admin toggle for the whole Analytics & Dashboards (BI) module,
    # mirroring the other jabvox_*_enabled_jabvox flags.
    add_column :accounts, :jabvox_analytics_enabled_jabvox, :boolean, default: false, null: false

    create_data_sources
    create_rbac
    create_data_source_permissions
    create_folders_and_dashboards
    create_widgets_and_filters
    create_shares_and_exports
    create_query_cache
    create_audit_logs
  end

  private

  # External database connections the account can query (read-only). Secrets are
  # stored AES-256-GCM encrypted via ActiveRecord::Encryption on the *_jabvox columns.
  def create_data_sources
    create_table :jabvox_analytics_data_sources do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :engine_jabvox, null: false # postgresql | mysql | mariadb | sqlite
      t.string :host_jabvox
      t.integer :port_jabvox
      t.string :database_jabvox
      t.string :username_jabvox
      t.text :password_jabvox # encrypted
      t.string :ssl_mode_jabvox, default: 'prefer', null: false
      t.text :ssl_ca_jabvox # encrypted
      t.string :sqlite_path_jabvox
      t.jsonb :options_jabvox, default: {}, null: false
      t.boolean :allow_private_network_jabvox, default: false, null: false # admin SSRF override
      t.integer :max_rows_jabvox, default: 1000, null: false
      t.integer :query_timeout_ms_jabvox, default: 30_000, null: false
      t.string :status_jabvox, default: 'untested', null: false # untested | ok | error
      t.datetime :last_tested_at_jabvox
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :name_jabvox], unique: true
    end
  end

  def create_rbac
    # RBAC roles per account. The 4 system roles are seeded and not deletable.
    create_table :jabvox_analytics_roles do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.string :slug_jabvox, null: false # admin | supervisor | analyst | viewer | custom-*
      t.boolean :is_system_jabvox, default: false, null: false
      t.string :description_jabvox, default: '', null: false
      t.timestamps
      t.index [:account_id, :slug_jabvox], unique: true
    end

    # Per-role grants for each permission key.
    create_table :jabvox_analytics_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: { to_table: :jabvox_analytics_roles }
      t.string :permission_key_jabvox, null: false
      t.boolean :granted_jabvox, default: false, null: false
      t.timestamps
      t.index [:account_id, :role_id, :permission_key_jabvox], unique: true, name: 'idx_jabvox_analytics_perms_unique'
    end

    # A user's assigned role within the analytics module + granular overrides.
    create_table :jabvox_analytics_user_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :role, foreign_key: { to_table: :jabvox_analytics_roles }, null: true
      t.jsonb :overrides_jabvox, default: {}, null: false
      t.timestamps
      t.index [:account_id, :user_id], unique: true
    end
  end

  # Which roles/users may use a given data source (and run custom SQL on it).
  def create_data_source_permissions
    create_table :jabvox_analytics_data_source_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :data_source, null: false, foreign_key: { to_table: :jabvox_analytics_data_sources }
      t.references :user, foreign_key: true, null: true
      t.references :role, foreign_key: { to_table: :jabvox_analytics_roles }, null: true
      t.boolean :can_query_jabvox, default: true, null: false
      t.boolean :can_use_custom_sql_jabvox, default: false, null: false
      t.timestamps
      t.index %i[data_source_id user_id], unique: true, name: 'idx_jabvox_analytics_dsp_user'
      t.index %i[data_source_id role_id], unique: true, name: 'idx_jabvox_analytics_dsp_role'
    end
  end

  def create_folders_and_dashboards
    # Folders organise dashboards into a tree.
    create_table :jabvox_analytics_folders do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.references :parent, foreign_key: { to_table: :jabvox_analytics_folders }, null: true
      t.integer :position_jabvox, default: 0, null: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :parent_id]
    end

    # A dashboard: a grid of widgets with global filters and a cache policy.
    create_table :jabvox_analytics_dashboards do |t|
      t.references :account, null: false, foreign_key: true
      t.references :folder, foreign_key: { to_table: :jabvox_analytics_folders }, null: true
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.jsonb :layout_jabvox, default: [], null: false      # per-widget x/y/w/h per breakpoint
      t.jsonb :global_filters_jabvox, default: [], null: false
      t.integer :cache_ttl_seconds_jabvox, default: 300, null: false
      t.boolean :is_template_jabvox, default: false, null: false
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index [:account_id, :folder_id]
    end
  end

  def create_widgets_and_filters
    # A single widget on a dashboard. Holds either a visual query spec or custom SQL,
    # plus viz config. widget_type_jabvox is one of the ~19 supported types.
    create_table :jabvox_analytics_dashboard_widgets do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dashboard, null: false, foreign_key: { to_table: :jabvox_analytics_dashboards }
      t.references :data_source, foreign_key: { to_table: :jabvox_analytics_data_sources }, null: true
      t.string :widget_type_jabvox, null: false
      t.string :title_jabvox, default: '', null: false
      t.jsonb :query_spec_jabvox, default: {}, null: false
      t.text :custom_sql_jabvox
      t.jsonb :config_jabvox, default: {}, null: false
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
      t.index [:account_id, :dashboard_id]
    end

    # Filter definitions (dashboard-global or per-widget).
    create_table :jabvox_analytics_widget_filters do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dashboard, foreign_key: { to_table: :jabvox_analytics_dashboards }, null: true
      t.references :widget, foreign_key: { to_table: :jabvox_analytics_dashboard_widgets }, null: true
      t.string :field_jabvox, null: false
      t.string :operator_jabvox, null: false
      t.jsonb :value_jabvox, default: {}, null: false
      t.string :filter_type_jabvox, null: false # date_range | select | multiselect | text | number
      t.boolean :is_global_jabvox, default: false, null: false
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
      t.index [:account_id, :dashboard_id]
      t.index [:account_id, :widget_id]
    end
  end

  def create_shares_and_exports
    # Sharing a dashboard with a user, role or team at a given access level.
    create_table :jabvox_analytics_shares do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dashboard, null: false, foreign_key: { to_table: :jabvox_analytics_dashboards }
      t.string :subject_type_jabvox, null: false # user | role | team
      t.bigint :subject_id_jabvox, null: false
      t.string :access_level_jabvox, null: false # view | edit | admin
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
      t.index %i[dashboard_id subject_type_jabvox subject_id_jabvox], unique: true, name: 'idx_jabvox_analytics_shares_unique'
    end

    # An export job (PDF/Excel/CSV) and its status/result.
    create_table :jabvox_analytics_exports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dashboard, foreign_key: { to_table: :jabvox_analytics_dashboards }, null: true
      t.references :user, null: false, foreign_key: true
      t.string :format_jabvox, null: false # pdf | excel | csv
      t.string :status_jabvox, default: 'pending', null: false # pending | processing | completed | failed
      t.string :file_url_jabvox
      t.text :error_jabvox
      t.jsonb :params_jabvox, default: {}, null: false
      t.datetime :expires_at_jabvox
      t.timestamps
      t.index [:account_id, :status_jabvox]
    end
  end

  # Durable query result cache (Redis holds hot/small results; this holds large/durable ones).
  def create_query_cache
    create_table :jabvox_analytics_query_cache do |t|
      t.references :account, null: false, foreign_key: true
      t.references :data_source, foreign_key: { to_table: :jabvox_analytics_data_sources }, null: true
      t.string :cache_key_jabvox, null: false
      t.jsonb :result_jabvox, default: {}, null: false
      t.integer :row_count_jabvox, default: 0, null: false
      t.datetime :expires_at_jabvox, null: false
      t.timestamps
      t.index [:account_id, :cache_key_jabvox], unique: true
      t.index :expires_at_jabvox
    end
  end

  # Append-only audit trail. Metadata is sanitized (never raw passwords or secret SQL).
  def create_audit_logs
    create_table :jabvox_analytics_audit_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true, null: true
      t.string :action_jabvox, null: false
      t.string :auditable_type_jabvox
      t.bigint :auditable_id_jabvox
      t.string :result_jabvox, null: false # success | failure | rejected
      t.string :ip_address_jabvox
      t.string :user_agent_jabvox
      t.jsonb :metadata_jabvox, default: {}, null: false
      t.datetime :created_at, null: false
      t.index [:account_id, :action_jabvox]
      t.index [:account_id, :created_at]
      t.index %i[account_id auditable_type_jabvox auditable_id_jabvox], name: 'idx_jabvox_analytics_audit_auditable'
    end
  end
end
