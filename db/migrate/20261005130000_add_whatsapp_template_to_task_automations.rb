# Mismo cambio que en las automatizaciones de etapa: el canal `inbox` enviaba texto libre,
# que WhatsApp solo acepta dentro de la ventana de 24h. Una automatización programada
# dispara casi siempre fuera de ella, así que el envío pasa a ser por plantilla aprobada.
class AddWhatsappTemplateToTaskAutomations < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_task_automations, bulk: true do |t|
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.jsonb :template_params_jabvox, null: false, default: {}
    end
  end
end
