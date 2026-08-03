# Cross-source reports: join data from SEVERAL external data sources (e.g. Wimpos'
# 4 separate SQL Server databases on different servers) that can't be JOINed in
# native SQL. The report declares which sources/tables participate and how they
# relate (mapping by a common field); the execution service pulls each source and
# joins the results in the app.
#
# Everything is scoped by account_id, per the golden rule (one tenant per report).
class CreateJabvoxAnalyticsCrossReports < ActiveRecord::Migration[7.1]
  def change
    # A cross-source report definition.
    create_table :jabvox_analytics_cross_reports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.integer :row_limit_jabvox, default: 1000, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Each participating source: a data source + a table + which columns to pull.
    create_table :jabvox_analytics_cross_sources do |t|
      t.references :cross_report, null: false,
                                  foreign_key: { to_table: :jabvox_analytics_cross_reports }
      t.references :data_source, null: false,
                                 foreign_key: { to_table: :jabvox_analytics_data_sources }
      t.string :table_jabvox, null: false
      t.string :alias_jabvox, null: false # unique short name used to qualify columns
      t.jsonb :columns_jabvox, default: [], null: false # [] = all columns
      t.jsonb :filters_jabvox, default: [], null: false # [{column, operator, value}]
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
    end
    add_index :jabvox_analytics_cross_sources, %i[cross_report_id alias_jabvox],
              unique: true, name: 'idx_cross_sources_report_alias'

    # The relations (the "mapping by a common field"): which column of one source
    # joins to which column of another, and the join type.
    create_table :jabvox_analytics_cross_joins do |t|
      t.references :cross_report, null: false,
                                  foreign_key: { to_table: :jabvox_analytics_cross_reports }
      t.references :left_source, null: false,
                                 foreign_key: { to_table: :jabvox_analytics_cross_sources }
      t.string :left_column_jabvox, null: false
      t.references :right_source, null: false,
                                  foreign_key: { to_table: :jabvox_analytics_cross_sources }
      t.string :right_column_jabvox, null: false
      t.string :join_type_jabvox, default: 'inner', null: false # inner | left
      t.integer :position_jabvox, default: 0, null: false
      t.timestamps
    end
  end
end
