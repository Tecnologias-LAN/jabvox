# Orquesta lo que ocurre tras crear un ticket: autoasignación (si la cuenta gestora
# la tiene activada) y notificación de creación a los resolvers. Se amplía en el
# bloque de notificaciones/jobs.
class Jabvox::Tickets::AfterCreateService
  def initialize(ticket, actor: nil)
    @ticket = ticket
    @actor = actor
  end

  def call
    Jabvox::Tickets::AutoAssignService.new(@ticket).call
    Jabvox::Tickets::NotificationService.new(@ticket, actor: @actor).ticket_created
  end
end
