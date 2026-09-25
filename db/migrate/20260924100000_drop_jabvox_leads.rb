# frozen_string_literal: true

# Retirada definitiva de Leads: todo vive ya en `contacts`.
#
# Un "lead" era una fila de `jabvox_leads` que apuntaba 1-a-1 a un contacto (contact_id es
# NOT NULL) y le añadía seis datos. Esos datos ya se copiaron a `contacts` en la migración
# 20260923100000, pero aquí se REPITE el volcado: entre aquella migración y ésta se pudieron
# crear o editar leads, y sus cambios no estarían reflejados.
#
# Orden deliberado: primero se vuelca, luego se verifica, y solo si la verificación pasa se
# sueltan las claves foráneas y se borran las tablas. Si algo no cuadra, la migración ABORTA
# sin haber borrado nada — es preferible un despliegue fallido a perder datos en silencio.
#
# Se CONSERVAN `jabvox_lead_sources` y `jabvox_lead_source_records`: pese al nombre no son
# leads, son el módulo de importación desde base de datos externa (con sus credenciales) y
# su tabla anti-duplicados. Aquí solo se repuntan al contacto y se les quita la FK al lead.
class DropJabvoxLeads < ActiveRecord::Migration[7.1]
  # Tablas que apuntan al lead y ya tienen `contact_id`: se rellena el contacto desde el
  # lead antes de soltar la columna.
  LEAD_DEPENDENTS = %w[
    jabvox_call_logs
    jabvox_custom_table_rows
    jabvox_kanban_conversation_stages
    jabvox_lead_source_records
    jabvox_task_lead_contacts
    jabvox_tasks
  ].freeze

  def up
    backfill_contacts_from_leads
    backfill_dependents_contact_id
    rename_leftover_leads_table
    verify_no_data_loss!

    drop_lead_columns
    drop_table :jabvox_task_lead_contacts, if_exists: true
    drop_table :jabvox_deleted_leads, if_exists: true
    drop_table :jabvox_leads, if_exists: true
    # Tabla sin modelo ni uso: el ciclo de vida se resuelve con una constante en el código.
    drop_table :jabvox_lead_lifecycle_stages, if_exists: true
  end

  # Irreversible a propósito: recrear las tablas vacías daría una falsa sensación de vuelta
  # atrás. Revertir esto es restaurar la copia de seguridad de la base de datos.
  def down
    raise ActiveRecord::IrreversibleMigration,
          'La retirada de Leads no se revierte: restaurar desde copia de seguridad.'
  end

  private

  # Vuelca al contacto lo que aún solo esté en el lead. Solo rellena lo que falta: un dato ya
  # editado en el contacto NO se pisa con el valor viejo del lead.
  #
  # `custom_fields_jabvox` se fusiona con el del lead como base, de modo que lo editado en el
  # contacto gana y no se pierde el historial del ciclo de vida que ya vive ahí.
  def backfill_contacts_from_leads
    execute(<<~SQL.squish)
      UPDATE contacts c SET
        jabvox_campaign_id   = COALESCE(c.jabvox_campaign_id, l.jabvox_campaign_id),
        jabvox_affiliate_id  = COALESCE(c.jabvox_affiliate_id, l.jabvox_affiliate_id),
        assignee_id          = COALESCE(c.assignee_id, l.assignee_id),
        is_sold_jabvox       = (c.is_sold_jabvox OR l.is_sold_jabvox),
        custom_fields_jabvox = COALESCE(l.custom_fields_jabvox, '{}'::jsonb)
                               || COALESCE(c.custom_fields_jabvox, '{}'::jsonb),
        became_lead_at_jabvox = COALESCE(c.became_lead_at_jabvox, l.created_at)
      FROM jabvox_leads l
      WHERE l.contact_id = c.id AND l.account_id = c.account_id
    SQL

    # Una venta implica cliente, igual que hace el modelo al guardar.
    execute(<<~SQL.squish)
      UPDATE contacts SET lifecycle_stage_jabvox = 'cliente'
      WHERE is_sold_jabvox = TRUE AND lifecycle_stage_jabvox <> 'cliente'
    SQL
  end

  # Cada fila dependiente hereda el contacto de su lead, si aún no lo tiene.
  def backfill_dependents_contact_id
    LEAD_DEPENDENTS.each do |table|
      next unless table_exists?(table) && column_exists?(table, :contact_id)

      execute(<<~SQL.squish)
        UPDATE #{table} t SET contact_id = l.contact_id
        FROM jabvox_leads l
        WHERE t.jabvox_lead_id = l.id AND t.contact_id IS NULL
      SQL
    end
  end

  # La tabla personalizada de contactos podía seguir llamándose "Leads": la migración que la
  # repuntó solo renombró las que existían entonces, y una cuenta pudo crearla después. Solo
  # se toca si conserva ese nombre por defecto; si el usuario la renombró, se respeta.
  def rename_leftover_leads_table
    return unless table_exists?(:jabvox_custom_tables)

    execute(<<~SQL.squish)
      UPDATE jabvox_custom_tables
         SET name_jabvox = 'Contactos'
       WHERE linked_to_jabvox = 'contacts' AND name_jabvox IN ('Leads', 'leads')
    SQL
  end

  # Última red antes de borrar. Si algo quedó sin contacto, la migración se detiene aquí
  # con las tablas todavía intactas.
  def verify_no_data_loss!
    orphan_leads = count_sql('SELECT COUNT(*) FROM jabvox_leads WHERE contact_id IS NULL')
    raise "#{orphan_leads} leads sin contacto: no se puede continuar sin perderlos" if orphan_leads.positive?

    LEAD_DEPENDENTS.each do |table|
      next unless table_exists?(table) && column_exists?(table, :contact_id)

      orphans = count_sql(<<~SQL.squish)
        SELECT COUNT(*) FROM #{table}
        WHERE jabvox_lead_id IS NOT NULL AND contact_id IS NULL
      SQL
      raise "#{table}: #{orphans} filas quedarían sin contacto al borrar leads" if orphans.positive?
    end
  end

  def count_sql(sql)
    select_value(sql).to_i
  end

  # Suelta la referencia al lead en cada tabla dependiente. `jabvox_task_lead_contacts` no
  # aparece aquí porque la tabla entera se borra después.
  def drop_lead_columns
    (LEAD_DEPENDENTS - %w[jabvox_task_lead_contacts]).each do |table|
      next unless table_exists?(table) && column_exists?(table, :jabvox_lead_id)

      # `contact_id` pasa a ser obligatorio donde el lead lo era, para que la integridad no
      # se relaje al retirar la columna vieja.
      change_column_null(table, :contact_id, false) if table == 'jabvox_lead_source_records'
      remove_column table, :jabvox_lead_id
    end
  end
end
