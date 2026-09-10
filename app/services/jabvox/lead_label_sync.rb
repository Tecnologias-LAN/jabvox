# Gestiona las etiquetas de un lead aplicándolas a las CONVERSACIONES abiertas de
# su contacto. El lead no tiene etiquetas propias (evita duplicar el sistema de
# labels de Chatwoot y romper el reporte de duración de etiquetas): las etiquetas
# "del lead" son en realidad las de sus conversaciones.
#
# - set_labels: reemplaza la lista completa de etiquetas.
# - add_label / remove_label: agregan o quitan una sola etiqueta.
# - labels_for: devuelve la lista actual (unión de las conversaciones abiertas).
#
# Se aplica a las conversaciones ABIERTAS del contacto (no reescribe historial
# resuelto), a través de Labelable#update_labels, disparando el reporte de labels.
module Jabvox
  class LeadLabelSync
    def initialize(account)
      @account = account
    end

    # Reemplaza las etiquetas de las conversaciones abiertas del lead con `labels`.
    def set_labels(lead, labels)
      each_open_conversation(lead) { |c| c.update_labels(Array(labels)) }
    end

    def add_label(lead, label)
      return if label.blank?

      each_open_conversation(lead) { |c| c.add_labels([label]) }
    end

    def remove_label(lead, label)
      return if label.blank?

      each_open_conversation(lead) { |c| c.update_labels(c.label_list - [label]) }
    end

    # Etiquetas actuales del lead = unión de las de sus conversaciones abiertas.
    def labels_for(lead)
      return [] if lead&.contact_id.blank?

      open_conversations(lead).flat_map(&:label_list).uniq.sort
    end

    private

    def each_open_conversation(lead)
      return if lead&.contact_id.blank?

      open_conversations(lead).find_each do |conversation|
        yield conversation
      rescue StandardError => e
        Rails.logger.error(
          "[LeadLabelSync] failed | conversation=#{conversation.id} #{e.class}: #{e.message}"
        )
      end
    end

    def open_conversations(lead)
      @account.conversations.where(contact_id: lead.contact_id, status: :open)
    end
  end
end
