# Las automatizaciones de etapa podían enviar texto libre por un inbox. En WhatsApp eso
# solo funciona dentro de la ventana de 24h: fuera de ella Meta rechaza el envío y la
# automatización fallaba en silencio. El envío pasa a ser por PLANTILLA aprobada, que es
# lo único que WhatsApp admite para iniciar conversación.
#
# `template_params_jabvox` guarda, por variable de la plantilla, de dónde sale su valor:
#   { "1" => { "source" => "contact", "field" => "name" },
#     "2" => { "source" => "task",    "field" => "title" },
#     "3" => { "source" => "custom",  "field" => "ciudad" },
#     "4" => { "source" => "fixed",   "value" => "Noviembre" } }
class AddWhatsappTemplateToStageAutomations < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_kanban_stage_automations, bulk: true do |t|
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.jsonb :template_params_jabvox, null: false, default: {}
    end

    change_table :jabvox_task_stage_automations, bulk: true do |t|
      t.string :template_name_jabvox
      t.string :template_language_jabvox
      t.jsonb :template_params_jabvox, null: false, default: {}
      # Kanban ya permitía elegir minutos u horas; tareas solo tenía horas.
      t.string :trigger_unit_jabvox
      t.integer :trigger_value_jabvox
    end
  end
end
