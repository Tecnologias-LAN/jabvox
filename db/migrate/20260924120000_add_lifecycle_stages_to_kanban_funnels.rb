# frozen_string_literal: true

# Cuarto origen para los embudos de Kanban: la ETAPA del contacto (prospecto, interesado,
# cliente, inactivo).
#
# Hasta ahora un embudo recogía conversaciones por bandeja, campaña o afiliado. Con Leads
# retirado, la etapa del ciclo de vida es el dato que sustituye a "es lead / no es lead", así
# que un embudo debe poder alimentarse de ella: por ejemplo, un embudo de reactivación que
# recoja solo los contactos inactivos.
#
# Se guarda como array de texto en el propio embudo (no una tabla puente) porque las etapas
# son un catálogo fijo y corto: no hay nada que referenciar.
class AddLifecycleStagesToKanbanFunnels < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_kanban_funnels, :lifecycle_stages_jabvox, :string, array: true, default: [], null: false
    add_index :jabvox_kanban_funnels, :lifecycle_stages_jabvox, using: :gin
  end
end
