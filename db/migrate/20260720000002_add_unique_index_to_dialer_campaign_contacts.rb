# frozen_string_literal: true

# Unicidad de contacto por campaña (auditoría D-12). Todo el dialer asume 1 fila
# por (campaña, contacto) —find_or_initialize_by, redial/exclude, mark_answered—
# pero no había índice único, así que operaciones concurrentes creaban duplicados
# y find_by tomaba la fila equivocada, inflando conteos.
#
# Las filas importadas con contact_id NULL no participan (índice parcial).
# Primero desduplica las filas existentes conservando la de intento más reciente.
class AddUniqueIndexToDialerCampaignContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    dedupe_existing!

    add_index :jabvox_dialer_campaign_contacts, %i[jabvox_dialer_campaign_id contact_id],
              unique: true,
              where: 'contact_id IS NOT NULL',
              name: 'idx_dialer_contacts_unique_campaign_contact',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :jabvox_dialer_campaign_contacts,
                 name: 'idx_dialer_contacts_unique_campaign_contact',
                 if_exists: true
  end

  private

  # Conserva, por cada (campaña, contacto), la fila con el último intento
  # (last_attempt_at más reciente; id como desempate) y borra las demás.
  # Los call_logs siguen a jabvox_dialer_campaign_contact_id de la fila borrada:
  # se re-apuntan a la fila conservada antes de borrar para no dejar huérfanos.
  def dedupe_existing!
    rows = execute(<<~SQL.squish).to_a
      SELECT jabvox_dialer_campaign_id AS campaign_id, contact_id, array_agg(id ORDER BY last_attempt_at_jabvox DESC NULLS LAST, id DESC) AS ids
      FROM jabvox_dialer_campaign_contacts
      WHERE contact_id IS NOT NULL
      GROUP BY jabvox_dialer_campaign_id, contact_id
      HAVING COUNT(*) > 1
    SQL

    rows.each do |row|
      ids = parse_pg_array(row['ids'])
      keep = ids.first
      drop = ids[1..] || []
      next if drop.empty?

      list = drop.join(',')
      execute("UPDATE jabvox_dialer_call_logs SET jabvox_dialer_campaign_contact_id = #{keep.to_i} " \
              "WHERE jabvox_dialer_campaign_contact_id IN (#{list})")
      execute("DELETE FROM jabvox_dialer_campaign_contacts WHERE id IN (#{list})")
    end
  end

  def parse_pg_array(value)
    return value if value.is_a?(Array)

    value.to_s.delete('{}').split(',').map(&:to_i)
  end
end
