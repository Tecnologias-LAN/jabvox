# Notificaciones de tickets por los tres canales: in-app (Notification/campanita),
# email (TicketMailer) y realtime (ActionCable, canal por cuenta con account_id).
# Un método por evento; decide a QUIÉN notificar y llama a los canales.
class Jabvox::Tickets::NotificationService
  def initialize(ticket, actor: nil)
    @ticket = ticket
    @actor = actor
    @account = ticket.account
  end

  # Creado → avisa a los resolvers (staff/agentes de la cuenta gestora).
  def ticket_created
    resolvers.each { |u| notify(u, :jabvox_ticket_created) }
    mail_resolvers(:new_ticket)
    broadcast('created')
  end

  # Asignado → al asignado.
  def ticket_assigned
    assignee = @ticket.assignee
    return if assignee.nil?

    notify(assignee, :jabvox_ticket_assigned)
    mail(assignee, :assigned)
    broadcast('assigned')
  end

  # Cambio de estado y resuelto → al solicitante.
  def status_changed
    notify(@ticket.requester, :jabvox_ticket_status_changed)
    broadcast('status_changed')
  end

  def ticket_resolved
    notify(@ticket.requester, :jabvox_ticket_resolved)
    mail(@ticket.requester, :resolved)
    broadcast('resolved')
  end

  # Reabierto → a los resolvers.
  def ticket_reopened
    resolvers.each { |u| notify(u, :jabvox_ticket_reopened) }
    broadcast('reopened')
  end

  # Comentario → a los participantes; las notas internas NO llegan al solicitante.
  def comment_added(comment)
    recipients = comment_recipients(comment)
    recipients.each { |u| notify(u, :jabvox_ticket_comment) }
    broadcast('comment')
  end

  # Escalamiento SLA → a los resolvers (usado por el job).
  def sla_escalated
    resolvers.each { |u| notify(u, :jabvox_ticket_sla_escalation) }
    broadcast('sla_escalation')
  end

  private

  def notify(user, type)
    return if user.nil? || user == @actor
    return unless Jabvox::Tickets::NotificationPreference.new(user).in_app?

    Notification.create!(account: @account, user: user, notification_type: type,
                         primary_actor: @ticket, secondary_actor: @actor)
  rescue StandardError => e
    JabvoxExceptionTracker.new(e, account: @account).capture_exception
  end

  # Envía un mail respetando la preferencia del destinatario.
  def mail(user, action)
    return if user.nil? || user == @actor
    return unless Jabvox::Tickets::NotificationPreference.new(user).email?

    TicketMailer.with(account: @account).public_send(action, @ticket, user).deliver_later
  rescue StandardError => e
    JabvoxExceptionTracker.new(e, account: @account).capture_exception
  end

  # Resolvers = usuarios de la cuenta gestora (staff + agentes).
  def resolvers
    account = JabvoxTicketHelpdeskConfig.manager_account
    account ? account.users.to_a : []
  end

  # A quién avisar de un comentario: solicitante + asignado, menos el autor. Si es
  # nota interna, se excluye al solicitante.
  def comment_recipients(comment)
    people = [@ticket.assignee, @ticket.requester].compact.uniq
    people -= [@ticket.requester] if comment.private_jabvox
    people - [comment.user]
  end

  def mail_resolvers(mailer_action)
    resolvers.each { |u| mail(u, mailer_action) }
  end

  def broadcast(event)
    ActionCable.server.broadcast(
      "account_#{@account.id}",
      { event: "jabvox.ticket_#{event}",
        data: { account_id: @account.id, ticket_id: @ticket.id,
                display_id: @ticket.display_id_jabvox, status: @ticket.status_jabvox } }
    )
  end
end
