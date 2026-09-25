# frozen_string_literal: true

# Últimos dos permisos de rol que seguían llamándose "lead": ya gateaban acciones sobre
# CONTACTOS, solo conservaban el nombre viejo.
#
# Los permisos se guardan como texto dentro de `custom_roles.permissions`, así que renombrar
# la constante en el código no basta: hay que reescribir los roles ya creados o un agente se
# quedaría sin el permiso que tenía concedido.
class RenameLeadRolePermissions < ActiveRecord::Migration[7.1]
  RENAMES = {
    'jabvox_leads_assign' => 'jabvox_contacts_assign',
    'jabvox_leads_edit' => 'jabvox_contacts_edit'
  }.freeze

  def up
    RENAMES.each { |old, new| rename_permission(old, new) }
  end

  def down
    RENAMES.each { |old, new| rename_permission(new, old) }
  end

  private

  # `permissions` es un array de texto en Postgres: se sustituye el elemento conservando el
  # resto, y solo en las filas que de verdad lo tienen.
  def rename_permission(from, to)
    execute(<<~SQL.squish)
      UPDATE custom_roles
      SET permissions = array_replace(permissions, #{quote(from)}, #{quote(to)})
      WHERE #{quote(from)} = ANY(permissions)
    SQL
  end
end
