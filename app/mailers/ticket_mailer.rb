# Correos del módulo de Tickets: nuevo ticket (a resolvers), asignado (al asignado)
# y resuelto (al solicitante). Usa plantillas ERB propias en views/ticket_mailer.
class TicketMailer < ApplicationMailer
  def new_ticket(ticket, recipient)
    return unless deliverable?(recipient)

    @ticket = ticket
    @recipient = recipient
    mail(to: recipient.email,
         subject: "Nuevo ticket ##{ticket.display_id_jabvox}: #{ticket.title_jabvox}")
  end

  def assigned(ticket, recipient)
    return unless deliverable?(recipient)

    @ticket = ticket
    @recipient = recipient
    mail(to: recipient.email,
         subject: "Se te asignó el ticket ##{ticket.display_id_jabvox}: #{ticket.title_jabvox}")
  end

  def resolved(ticket, recipient)
    return unless deliverable?(recipient)

    @ticket = ticket
    @recipient = recipient
    mail(to: recipient.email,
         subject: "Tu ticket ##{ticket.display_id_jabvox} fue resuelto")
  end

  private

  def deliverable?(recipient)
    recipient&.email.present? && smtp_config_set_or_development?
  end
end
