# Mapeo responsable (assignee/User) -> contacto, para automatizaciones de tarea por
# WhatsApp. Un responsable es un usuario sin teléfono ni contacto; para enviarle una
# plantilla aprobada hace falta un contacto real (con número E.164 y contact_inbox).
# Esta columna guarda, por cada responsable, qué contacto usar: { "<user_id>" => <contact_id> }.
class AddAssigneeContactMapToTaskAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_automations, :assignee_contact_map_jabvox, :jsonb, null: false, default: {}
  end
end
