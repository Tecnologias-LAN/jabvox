# Base del módulo de Tickets (helpdesk central). El feature 'jabvox_tickets' habilita
# que los usuarios de la cuenta REGISTREN tickets. El acceso de lectura/gestión lo
# gobierna JabvoxTicketPolicy (staff = admin de la cuenta gestora ve todo; resolver =
# agente de la gestora ve lo asignado; requester = solo lo suyo). Por eso el scope de
# tickets es GLOBAL y la policy lo filtra — no se limita a Current.account.
class Api::V1::Accounts::Jabvox::Tickets::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_tickets_enabled

  rescue_from Jabvox::TicketLifecycle::InvalidTransitionError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from ActiveRecord::StaleObjectError do
    render json: { error: 'El ticket fue modificado por otra persona. Recarga y vuelve a intentar.' },
           status: :conflict
  end

  private

  def check_tickets_enabled
    return if Current.account.feature_enabled?('jabvox_tickets')

    render json: { error: 'El módulo de Tickets no está habilitado para esta cuenta' },
           status: :forbidden
  end

  def ticket_permission
    @ticket_permission ||= Jabvox::TicketPermissionResolver.new(Current.user)
  end
end
