class Api::V1::Accounts::Jabvox::ResponseBotRolesController < Api::V1::Accounts::Jabvox::BaseController
  def index
    authorize JabvoxResponseBotRole
    render json: JabvoxResponseBotRole.active.ordered.map { |r| role_json(r) }
  end

  private

  def role_json(role)
    { id: role.id, name_jabvox: role.name_jabvox, active_jabvox: role.active_jabvox }
  end
end
