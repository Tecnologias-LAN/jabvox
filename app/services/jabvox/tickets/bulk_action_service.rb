# Ejecuta una acción sobre varios tickets a la vez (asignar / cambiar estado /
# archivar). Cada ticket pasa por la policy (vía el bloque `policy`), de modo que el
# usuario solo afecta lo que puede. Devuelve un resumen ok/fallidos.
class Jabvox::Tickets::BulkActionService
  ACTIONS = %w[assign change_status archive].freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, actor:, policy:, action:, ids:, value: nil)
    @account = account
    @actor = actor
    @policy = policy # callable (ticket, query) que hace authorize
    @action = action.to_s
    @ids = ids.map(&:to_i).uniq
    @value = value
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return { error: 'Acción no soportada' } unless ACTIONS.include?(@action)

    processed = []
    failed = []
    tickets.each do |ticket|
      apply(ticket)
      processed << ticket.id
    rescue StandardError
      failed << ticket.id
    end
    { processed: processed, failed: failed, total: @ids.size }
  end

  private

  def tickets
    JabvoxTicket.where(id: @ids)
  end

  def apply(ticket)
    case @action
    when 'assign' then bulk_assign(ticket)
    when 'change_status' then bulk_change_status(ticket)
    when 'archive' then bulk_archive(ticket)
    end
  end

  def bulk_assign(ticket)
    @policy.call(ticket, :assign?)
    assignee = @value.present? ? User.find(@value) : nil
    ticket.assign_to!(assignee, actor: @actor)
  end

  def bulk_change_status(ticket)
    @policy.call(ticket, :change_status?)
    ticket.change_status!(@value, actor: @actor)
  end

  def bulk_archive(ticket)
    @policy.call(ticket, :destroy?)
    ticket.archive!(actor: @actor)
  end
end
