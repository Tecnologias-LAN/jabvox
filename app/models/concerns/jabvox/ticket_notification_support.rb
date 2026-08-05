# Hace que Notification soporte tickets como primary_actor sin romper el flujo de
# Conversation. Los métodos del core (primary_actor_data / push_message_title /
# push_message_body) asumen Conversation; aquí interceptamos SOLO cuando el
# primary_actor es un JabvoxTicket y delegamos al super en el resto de casos.
module Jabvox::TicketNotificationSupport
  def primary_actor_data
    return jabvox_ticket_actor_data if jabvox_ticket_notification?

    super
  end

  def push_message_title
    return jabvox_ticket_title if jabvox_ticket_notification?

    super
  end

  def push_message_body
    return jabvox_ticket_body if jabvox_ticket_notification?

    super
  end

  private

  def jabvox_ticket_notification?
    primary_actor_type == 'JabvoxTicket'
  end

  def jabvox_ticket_actor_data
    { primary_actor: { id: primary_actor.id, display_id: primary_actor.display_id_jabvox,
                       title: primary_actor.title_jabvox, status: primary_actor.status_jabvox } }
  end

  def jabvox_ticket_title
    I18n.t("jabvox_tickets.notifications.#{notification_type}.title",
           id: primary_actor.display_id_jabvox,
           default: "Ticket ##{primary_actor.display_id_jabvox}")
  end

  def jabvox_ticket_body
    primary_actor.title_jabvox
  end
end
