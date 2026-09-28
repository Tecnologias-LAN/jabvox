# frozen_string_literal: true

# Mantiene iguales las etiquetas de un contacto y las de sus conversaciones ABIERTAS.
#
# En Chatwoot son entidades separadas: un contacto tiene sus etiquetas y cada conversación
# las suyas. Para el trabajo comercial de Jabvox esa distinción sobra —cuando alguien
# etiqueta "cliente VIP" espera verlo en los dos sitios— así que aquí se propagan.
#
# Dos decisiones deliberadas:
#
#   - Solo se tocan las conversaciones ABIERTAS. Una resuelta es historial: reescribir sus
#     etiquetas falsearía con qué se cerró el caso.
#   - La propagación no vuelve a disparar la sincronización (`skip_jabvox_label_sync`), o
#     contacto y conversación se llamarían en bucle.
class Jabvox::LabelSyncService
  def initialize(record)
    @record = record
  end

  # Un contacto recién etiquetado empuja su lista a sus conversaciones abiertas.
  # Una conversación recién etiquetada empuja la suya al contacto, y de ahí al resto de
  # conversaciones abiertas de ese contacto: así las dos direcciones convergen.
  def call
    return if @record.skip_jabvox_label_sync

    case @record
    when Contact then push_to_conversations(@record, @record.label_list)
    when Conversation then push_from_conversation
    end
  end

  private

  def push_from_conversation
    contact = @record.contact
    return if contact.blank?

    sync(contact, @record.label_list)
    push_to_conversations(contact, @record.label_list, except: @record.id)
  end

  def push_to_conversations(contact, labels, except: nil)
    scope = contact.conversations.where(status: :open)
    scope = scope.where.not(id: except) if except
    scope.each { |conversation| sync(conversation, labels) }
  end

  # `update_labels` reemplaza la lista entera, que es justo lo que se quiere: los dos lados
  # acaban con el mismo conjunto. Se salta si ya coinciden para no generar actividad inútil.
  def sync(target, labels)
    return if target.label_list.sort == Array(labels).sort

    target.skip_jabvox_label_sync = true
    target.update_labels(labels)
  ensure
    target.skip_jabvox_label_sync = false
  end
end
