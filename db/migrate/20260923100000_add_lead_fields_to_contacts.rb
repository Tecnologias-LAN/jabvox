# frozen_string_literal: true

# Primer paso de la unificación Leads → Contactos.
#
# Hoy un "lead" es una fila de `jabvox_leads` que apunta 1-a-1 a un contacto y le añade seis
# datos (campaña, afiliado, responsable, venta, campos personalizados). Eso obliga a mantener
# dos pantallas y a que cada módulo decida contra cuál de los dos consultar.
#
# Aquí esos datos pasan a vivir en `contacts`, más el ciclo de vida que sustituye la
# distinción "es lead / no es lead": todo contacto nace como `prospecto` y avanza a
# interesado → cliente → inactivo.
#
# Es ADITIVA a propósito: no borra ni modifica nada de `jabvox_leads`, así que producción
# sigue funcionando igual mientras los módulos se redirigen uno a uno. El borrado de leads
# es un paso posterior y separado.
#
# `lead_number` NO se migra: es un identificador de la vieja pantalla que ya no se necesita.
class AddLeadFieldsToContacts < ActiveRecord::Migration[7.1]
  LIFECYCLE_DEFAULT = 'prospecto'

  def up
    add_column :contacts, :jabvox_campaign_id, :bigint
    add_column :contacts, :jabvox_affiliate_id, :bigint
    add_column :contacts, :assignee_id, :bigint
    add_column :contacts, :is_sold_jabvox, :boolean, default: false, null: false
    add_column :contacts, :custom_fields_jabvox, :jsonb, default: {}, null: false
    add_column :contacts, :lifecycle_stage_jabvox, :string, default: LIFECYCLE_DEFAULT, null: false
    # Marca de origen: distingue el contacto que venía de la pantalla de Leads del que nació
    # de una conversación. Sirve para no perder esa información al retirar la tabla.
    add_column :contacts, :became_lead_at_jabvox, :datetime

    # Mismos índices que tenía jabvox_leads, para que los filtros de la lista no se degraden.
    add_index :contacts, %i[account_id jabvox_campaign_id]
    add_index :contacts, %i[account_id jabvox_affiliate_id]
    add_index :contacts, %i[account_id lifecycle_stage_jabvox]
    add_index :contacts, :assignee_id
    add_index :contacts, :is_sold_jabvox
    add_index :contacts, :custom_fields_jabvox, using: :gin

    backfill_from_leads
  end

  def down
    %i[account_id_and_jabvox_campaign_id account_id_and_jabvox_affiliate_id
       account_id_and_lifecycle_stage_jabvox assignee_id is_sold_jabvox
       custom_fields_jabvox].each do |idx|
      remove_index :contacts, name: "index_contacts_on_#{idx}" if index_name_exists?(:contacts, "index_contacts_on_#{idx}")
    end
    remove_column :contacts, :jabvox_campaign_id
    remove_column :contacts, :jabvox_affiliate_id
    remove_column :contacts, :assignee_id
    remove_column :contacts, :is_sold_jabvox
    remove_column :contacts, :custom_fields_jabvox
    remove_column :contacts, :lifecycle_stage_jabvox
    remove_column :contacts, :became_lead_at_jabvox
  end

  private

  # Copia los datos de cada lead a su contacto. Un UPDATE ... FROM en vez de recorrer en Ruby:
  # en cuentas con cientos de miles de leads la diferencia es de minutos a segundos.
  #
  # `is_sold_jabvox` marca al contacto como CLIENTE: una venta cerrada es exactamente eso, y
  # así el ciclo de vida queda poblado desde el primer día en vez de dejar todo en prospecto.
  def backfill_from_leads
    return unless table_exists?(:jabvox_leads)

    execute(<<~SQL.squish)
      UPDATE contacts c
         SET jabvox_campaign_id     = l.jabvox_campaign_id,
             jabvox_affiliate_id    = l.jabvox_affiliate_id,
             assignee_id            = l.assignee_id,
             is_sold_jabvox         = COALESCE(l.is_sold_jabvox, false),
             custom_fields_jabvox   = COALESCE(l.custom_fields_jabvox, '{}'::jsonb),
             lifecycle_stage_jabvox = CASE WHEN l.is_sold_jabvox THEN 'cliente' ELSE '#{LIFECYCLE_DEFAULT}' END,
             became_lead_at_jabvox  = l.created_at
        FROM jabvox_leads l
       WHERE l.contact_id = c.id
         AND l.account_id = c.account_id
    SQL
  end
end
