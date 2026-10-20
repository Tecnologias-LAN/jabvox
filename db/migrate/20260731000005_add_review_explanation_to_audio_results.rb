# Cuando el score de la primera validación cae bajo el umbral, una segunda
# validación (auditoría) revisa la primera, puede corregirla y explica en detalle
# por qué la llamada quedó con ese porcentaje. Se guarda aquí para mostrarlo en el
# reporte/PDF.
class AddReviewExplanationToAudioResults < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_audio_results, :review_explanation, :text
    # Score de la primera pasada, antes de la auditoría (para trazabilidad).
    add_column :jabvox_audio_results, :first_pass_score, :integer
  end
end
