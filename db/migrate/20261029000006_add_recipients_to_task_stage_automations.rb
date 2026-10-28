# Destinatario configurable en las automatizaciones DE ETAPA de tareas (antes el mensaje
# siempre iba al contacto del lead). Igual que en las automatizaciones de tarea específica:
#   - recipients_jabvox: a quién enviar ("lead", "assignees", "manual", combinables por coma).
#     default "lead" para no cambiar el comportamiento de las automatizaciones ya creadas.
#   - assignee_contact_map_jabvox: { "<user_id>" => <contact_id> } para poder enviar la
#     plantilla de WhatsApp a un responsable (un User no tiene teléfono ni contacto propio).
#   - manual_email/phone: destinatario escrito a mano.
class AddRecipientsToTaskStageAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_task_stage_automations, :recipients_jabvox, :string, null: false, default: 'lead'
    add_column :jabvox_task_stage_automations, :assignee_contact_map_jabvox, :jsonb, null: false, default: {}
    add_column :jabvox_task_stage_automations, :manual_email_jabvox, :string, null: false, default: ''
    add_column :jabvox_task_stage_automations, :manual_phone_jabvox, :string, null: false, default: ''
  end
end
