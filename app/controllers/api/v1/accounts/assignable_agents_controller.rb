class Api::V1::Accounts::AssignableAgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_inboxes

  def index
    # Jabvox: cualquier agente de la cuenta es asignable, sin importar si es
    # miembro de la bandeja (así se puede asignar a quien no ve todas las
    # conversaciones). Solo validamos acceso a la bandeja del que consulta.
    # TODO: Remove this opt-in once mobile clients support AgentBot assignees in this payload.
    @include_agent_bots = params[:include_agent_bots].present?
    @inboxes.each { |inbox| authorize inbox, :show? }
    @assignable_agents = Current.account.users.uniq
    @agent_bots = @include_agent_bots ? AgentBot.accessible_to(Current.account) : []
  end

  private

  def fetch_inboxes
    @inboxes = Current.account.inboxes.find(permitted_params[:inbox_ids])
  end

  def permitted_params
    params.permit(inbox_ids: [])
  end
end
