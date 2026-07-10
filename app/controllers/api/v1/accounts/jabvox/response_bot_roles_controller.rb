class Api::V1::Accounts::Jabvox::ResponseBotRolesController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission

  def index
    authorize JabvoxResponseBotRole
    render json: JabvoxResponseBotRole.active.ordered.map { |r| role_json(r) }
  end

  private

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_response_bot_manage')
  end

  def role_json(role)
    { id: role.id, name_jabvox: role.name_jabvox, active_jabvox: role.active_jabvox }
  end
end
