module Labelable
  extend ActiveSupport::Concern

  included do
    acts_as_taggable_on :labels

    # Bandera en memoria (no es columna) para cortar el ida y vuelta: cuando la
    # sincronización propaga una lista, el destino no debe volver a propagarla.
    attr_accessor :skip_jabvox_label_sync
  end

  # Devuelve lo de `update!` (true): hay código que depende de ese valor de retorno, así
  # que la sincronización no debe cambiarlo.
  def update_labels(labels = nil)
    result = update!(label_list: labels)
    sync_jabvox_labels
    result
  end

  def add_labels(new_labels = nil)
    return if new_labels.blank?

    new_labels = Array(new_labels) # Make sure new_labels is an array
    combined_labels = labels + new_labels
    result = update!(label_list: combined_labels)
    sync_jabvox_labels
    result
  end

  private

  # Un contacto y sus conversaciones abiertas comparten etiquetas: etiquetar en un sitio
  # debe verse en el otro. Ver Jabvox::LabelSyncService para el porqué y sus límites.
  def sync_jabvox_labels
    return unless is_a?(Contact) || is_a?(Conversation)

    Jabvox::LabelSyncService.new(self).call
  end
end
