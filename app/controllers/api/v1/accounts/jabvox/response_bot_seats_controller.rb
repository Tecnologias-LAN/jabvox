class Api::V1::Accounts::Jabvox::ResponseBotSeatsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission

  def index
    authorize JabvoxResponseBotSeat
    render json: JabvoxResponseBotSeat.active.ordered.map { |s| seat_json(s) }
  end

  private

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_response_bot_manage')
  end

  def seat_json(seat)
    { id: seat.id, name_jabvox: seat.name_jabvox, active_jabvox: seat.active_jabvox }
  end
end
