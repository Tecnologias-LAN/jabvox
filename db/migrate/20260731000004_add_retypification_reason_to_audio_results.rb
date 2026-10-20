# Guarda la justificación de la IA cuando considera que la llamada estaba mal
# tipificada (p. ej. "tipificada como Correteo pero se asemeja más a Asesoría
# porque..."), igual que la columna "Tipificación correcta" del ejercicio humano.
class AddRetypificationReasonToAudioResults < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_audio_results, :retypification_reason, :text
  end
end
