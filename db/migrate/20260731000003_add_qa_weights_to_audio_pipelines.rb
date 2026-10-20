# Pesos del score global de QA, configurables por pipeline. El documento de
# Anatomía LikeU plantea que la anatomía arranca como módulo cualitativo y que,
# "tras calibración", puede tener peso dentro del resultado global. Esto habilita
# esa calibración sin tocar código:
#   score_global = infaltables% * (w_inf/100) + anatomía% * (w_ana/100)
# Por defecto 100/0 → el score es solo % de infaltables (comportamiento actual).
class AddQaWeightsToAudioPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_audio_pipelines, :qa_infaltables_weight_jabvox, :integer, null: false, default: 100
    add_column :jabvox_audio_pipelines, :qa_anatomy_weight_jabvox, :integer, null: false, default: 0
  end
end
