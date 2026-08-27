# Devuelve el rol del usuario actual en el helpdesk ({staff, resolver, manager}),
# para que el frontend muestre/oculte acciones y paneles.
class Api::V1::Accounts::Jabvox::Tickets::PermissionsController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  def show
    render json: ticket_permission.to_permissions
  end
end
