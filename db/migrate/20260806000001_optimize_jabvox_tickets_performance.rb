# Optimización de rendimiento del módulo de tickets (P0):
# - Saca los flags de SLA del jsonb a columnas reales indexables (evita scan del job cada 15 min).
# - Índice parcial para lo caliente (tickets abiertos por vencimiento).
# - Full-text search con tsvector + índice GIN (reemplaza ILIKE '%...%').
# - lock_version (bloqueo optimista) y comments_count (counter_cache).
# - deleted_at (soft delete / archivado).
# - Config del helpdesk: horario laboral y modo de visibilidad del resolver.
class OptimizeJabvoxTicketsPerformance < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_sla_columns
    add_optimistic_and_counter_columns
    add_soft_delete_column
    add_fulltext_column
    add_config_columns
    add_performance_indexes
  end

  private

  # Flags de SLA como columnas reales (antes en custom_attributes_jabvox jsonb).
  def add_sla_columns
    add_column :jabvox_tickets, :sla_escalated_at_jabvox, :datetime unless column_exists?(:jabvox_tickets, :sla_escalated_at_jabvox)
    add_column :jabvox_tickets, :sla_warned_at_jabvox, :datetime unless column_exists?(:jabvox_tickets, :sla_warned_at_jabvox)
  end

  def add_optimistic_and_counter_columns
    add_column :jabvox_tickets, :lock_version, :integer, null: false, default: 0 unless column_exists?(:jabvox_tickets, :lock_version)
    return if column_exists?(:jabvox_tickets, :comments_count_jabvox)

    add_column :jabvox_tickets, :comments_count_jabvox, :integer, null: false, default: 0
  end

  def add_soft_delete_column
    add_column :jabvox_tickets, :deleted_at_jabvox, :datetime unless column_exists?(:jabvox_tickets, :deleted_at_jabvox)
  end

  # Columna tsvector generada para búsqueda full-text sobre título + descripción.
  def add_fulltext_column
    return if column_exists?(:jabvox_tickets, :search_vector_jabvox)

    execute(<<~SQL.squish)
      ALTER TABLE jabvox_tickets
      ADD COLUMN search_vector_jabvox tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(title_jabvox, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(description_jabvox, '')), 'B')
      ) STORED
    SQL
  end

  # Config del helpdesk: horario laboral (jsonb) y visibilidad del resolver.
  def add_config_columns
    unless column_exists?(:jabvox_ticket_helpdesk_configs, :business_hours_jabvox)
      add_column :jabvox_ticket_helpdesk_configs, :business_hours_jabvox, :jsonb, null: false, default: {}
    end
    return if column_exists?(:jabvox_ticket_helpdesk_configs, :resolver_visibility_jabvox)

    # 0 = solo asignado (por defecto), 1 = bandeja completa
    add_column :jabvox_ticket_helpdesk_configs, :resolver_visibility_jabvox, :integer, null: false, default: 0
  end

  def add_performance_indexes
    add_open_due_index
    add_sla_escalation_index
    add_fulltext_index
    add_soft_delete_index
    add_comments_ticket_created_index
  end

  # Índice parcial de lo caliente: tickets NO resueltos/cerrados ordenados por vencimiento.
  def add_open_due_index
    return if index_exists?(:jabvox_tickets, [:account_id, :due_at_jabvox], name: 'idx_tickets_open_due')

    add_index :jabvox_tickets, [:account_id, :due_at_jabvox],
              name: 'idx_tickets_open_due',
              where: 'status_jabvox NOT IN (4, 5) AND deleted_at_jabvox IS NULL',
              algorithm: :concurrently
  end

  # Índice parcial para el job SLA: abiertos vencidos aún sin escalar.
  def add_sla_escalation_index
    return if index_exists?(:jabvox_tickets, :due_at_jabvox, name: 'idx_tickets_sla_pending')

    add_index :jabvox_tickets, :due_at_jabvox,
              name: 'idx_tickets_sla_pending',
              where: 'status_jabvox NOT IN (4, 5) AND sla_escalated_at_jabvox IS NULL AND deleted_at_jabvox IS NULL',
              algorithm: :concurrently
  end

  def add_fulltext_index
    return if index_exists?(:jabvox_tickets, :search_vector_jabvox, name: 'idx_tickets_search_vector')

    add_index :jabvox_tickets, :search_vector_jabvox,
              name: 'idx_tickets_search_vector', using: :gin, algorithm: :concurrently
  end

  def add_soft_delete_index
    return if index_exists?(:jabvox_tickets, [:account_id, :deleted_at_jabvox], name: 'idx_tickets_account_deleted')

    add_index :jabvox_tickets, [:account_id, :deleted_at_jabvox],
              name: 'idx_tickets_account_deleted', algorithm: :concurrently
  end

  def add_comments_ticket_created_index
    return if index_exists?(:jabvox_ticket_comments, [:ticket_id, :created_at], name: 'idx_ticket_comments_ticket_created')

    add_index :jabvox_ticket_comments, [:ticket_id, :created_at],
              name: 'idx_ticket_comments_ticket_created', algorithm: :concurrently
  end
end
