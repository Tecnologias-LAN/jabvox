# frozen_string_literal: true

# Renombra los permisos que todavía hablaban de "leads" ahora que la pantalla unificada es
# Contactos. El permiso vive como string dentro del array `permissions` de cada rol
# personalizado, así que hay que reescribir esas filas: si solo se cambiara el nombre en el
# código, los roles ya guardados dejarían de conceder nada y los agentes perderían accesos
# sin aviso.
#
# Se mantiene el nombre viejo como ALIAS en el código (ver JabvoxPermissions) para que un rol
# que no se alcanzara a migrar —por ejemplo el de una cuenta creada entre el despliegue y la
# migración— siga funcionando.
class RenameLeadPermissionsToContacts < ActiveRecord::Migration[7.1]
  RENAMES = {
    'jabvox_leads_view_all' => 'jabvox_contacts_view_all',
    'jabvox_leads_manage' => 'jabvox_contacts_manage',
    'jabvox_leads_delete' => 'jabvox_contacts_delete'
  }.freeze

  def up
    RENAMES.each { |old, new| swap_permission(old, new) }
  end

  def down
    RENAMES.each { |old, new| swap_permission(new, old) }
  end

  private

  # array_replace reescribe el elemento dentro del array sin tocar el resto de permisos del
  # rol; el WHERE evita actualizar filas que no lo tienen.
  def swap_permission(from, to)
    return unless table_exists?(:custom_roles)

    execute(<<~SQL.squish)
      UPDATE custom_roles
         SET permissions = array_replace(permissions, '#{from}', '#{to}')
       WHERE '#{from}' = ANY(permissions)
    SQL
  end
end
