class Api::V1::Accounts::Jabvox::ResponseBotSeatsController < Api::V1::Accounts::Jabvox::BaseController
  def index
    authorize JabvoxResponseBotSeat
    render json: JabvoxResponseBotSeat.active.ordered.map { |s| seat_json(s) }
  end

  private

  def seat_json(seat)
    { id: seat.id, name_jabvox: seat.name_jabvox, active_jabvox: seat.active_jabvox }
  end
end
