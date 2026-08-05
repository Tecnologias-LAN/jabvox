# Autoasignación de un ticket recién creado, según el modo configurado en la cuenta
# gestora del helpdesk:
#   manual       → no asigna (el staff lo toma)
#   round_robin  → al resolver (agente de la gestora) con menos tickets abiertos
#   by_category  → al responsable de la categoría del ticket
# Idempotente: no reasigna si el ticket ya tiene assignee.
class Jabvox::Tickets::AutoAssignService
  def initialize(ticket)
    @ticket = ticket
    @config = JabvoxTicketHelpdeskConfig.current
  end

  def call
    return if @config.nil? || @ticket.assignee_id.present?

    assignee = pick_assignee
    @ticket.assign_to!(assignee) if assignee
  end

  private

  def pick_assignee
    case @config.auto_assign_mode_jabvox
    when 'round_robin' then least_loaded_resolver
    when 'by_category' then @ticket.category&.responsible
    end
  end

  # Agentes de la cuenta gestora (resolvers) ordenados por menor carga abierta.
  def least_loaded_resolver
    resolvers = @config.account.users
    return nil if resolvers.blank?

    load_by_user = JabvoxTicket.open_tickets.where(assignee_id: resolvers.select(:id))
                               .group(:assignee_id).count
    resolvers.min_by { |u| load_by_user[u.id] || 0 }
  end
end
