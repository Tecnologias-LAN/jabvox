# Permite que el QA, cuando la IA detecta que la llamada corresponde a OTRA
# tipificación (mal tipificada), re-evalúe con los infaltables de la tipificación
# correcta — igual que hace el analista humano, que califica sobre la tipificación
# real y no sobre la etiqueta con la que llegó la llamada.
class AddReclassifyToAudioPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_audio_pipelines, :qa_reclassify_jabvox, :boolean, null: false, default: true
  end
end
