# frozen_string_literal: true

# `include_own_leads_jabvox` pasa a `include_own_contacts_jabvox`: con Leads unificado en
# Contactos, la opción significa "incluir los contactos propios de la cuenta" (los que no
# vinieron de un afiliado), no leads.
#
# rename_column conserva los valores, así que ningún embudo pierde su configuración.
class RenameIncludeOwnLeadsOnKanbanFunnels < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:jabvox_kanban_funnels, :include_own_leads_jabvox)

    rename_column :jabvox_kanban_funnels, :include_own_leads_jabvox, :include_own_contacts_jabvox
  end

  def down
    return unless column_exists?(:jabvox_kanban_funnels, :include_own_contacts_jabvox)

    rename_column :jabvox_kanban_funnels, :include_own_contacts_jabvox, :include_own_leads_jabvox
  end
end
