# frozen_string_literal: true

# Segundo paso de la unificación: las tablas que apuntaban al lead ahora apuntan también al
# contacto, para que cada módulo (kanban, tareas, dialer, afiliados) pueda dejar de consultar
# `jabvox_leads` sin perder sus datos.
#
# Se AÑADE contact_id y se rellena desde el lead; la columna vieja se conserva. Así el código
# puede migrarse módulo a módulo y, si algo falla, se vuelve a la columna anterior sin
# restaurar nada. El borrado de jabvox_lead_id es un paso posterior y separado.
class AddContactIdToLeadDependentTables < ActiveRecord::Migration[7.1]
  # Sin transacción envolvente: dentro de una, el UPDATE no ve las columnas que esta misma
  # migración acaba de crear. Cada paso es idempotente (comprueba antes de crear y el
  # backfill filtra por IS NULL), así que reejecutarla tras un fallo es seguro.
  disable_ddl_transaction!

  # tabla => columna que referencia al lead
  TABLES = {
    jabvox_kanban_conversation_stages: :jabvox_lead_id,
    jabvox_tasks: :jabvox_lead_id,
    jabvox_task_lead_contacts: :jabvox_lead_id,
    jabvox_lead_source_records: :jabvox_lead_id
  }.freeze
  # jabvox_bulk_whatsapp_recipients.lead_id_jabvox queda FUERA a propósito: es un string
  # (identificador externo del destinatario), no una FK a jabvox_leads, y ya tiene su propio
  # contact_id.

  def up
    # Primero TODAS las columnas y luego TODOS los backfills: dentro de la misma transacción
    # el planificador no ve una columna recién creada si el UPDATE se prepara antes, así que
    # separar las dos fases evita el "column does not exist" a mitad de migración.
    TABLES.each_key { |table| add_contact_column(table) if table_exists?(table) }
    TABLES.each { |table, lead_column| backfill(table, lead_column) if table_exists?(table) }
  end

  def down
    TABLES.each_key do |table|
      next unless table_exists?(table) && column_exists?(table, :contact_id)
      # Solo se retira donde esta migración la creó: jabvox_call_logs y
      # jabvox_custom_table_rows ya tenían contact_id de antes y no deben perderla.
      next if %i[jabvox_call_logs jabvox_custom_table_rows].include?(table)

      remove_index table, %i[account_id contact_id] if index_exists?(table, %i[account_id contact_id])
      remove_column table, :contact_id
    end
  end

  private

  def add_contact_column(table)
    return if column_exists?(table, :contact_id)

    add_column table, :contact_id, :bigint
    # Índice compuesto: la consulta real siempre acota por cuenta además de por contacto.
    add_index table, %i[account_id contact_id] if column_exists?(table, :account_id)
  end

  # Copia el contacto de cada lead. UPDATE ... FROM en vez de recorrer en Ruby: en cuentas
  # grandes la diferencia es de minutos a segundos.
  def backfill(table, lead_column)
    execute(<<~SQL.squish)
      UPDATE #{table} t
         SET contact_id = l.contact_id
        FROM jabvox_leads l
       WHERE l.id = t.#{lead_column}
         AND t.contact_id IS NULL
    SQL
  end
end
