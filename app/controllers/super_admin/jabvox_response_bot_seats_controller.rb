class SuperAdmin::JabvoxResponseBotSeatsController < SuperAdmin::ApplicationController
  before_action :set_seat, only: [:edit, :update, :destroy]

  def index
    @seats = JabvoxResponseBotSeat.ordered
  end

  def new
    @seat = JabvoxResponseBotSeat.new
  end

  def edit; end

  def create
    @seat = JabvoxResponseBotSeat.new(seat_params)
    if @seat.save
      redirect_to super_admin_jabvox_response_bot_seats_path, notice: 'Acento created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @seat.update(seat_params)
      redirect_to super_admin_jabvox_response_bot_seats_path, notice: 'Acento updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @seat.destroy!
    redirect_to super_admin_jabvox_response_bot_seats_path, notice: 'Acento deleted.'
  end

  private

  def set_seat
    @seat = JabvoxResponseBotSeat.find(params[:id])
  end

  def seat_params
    params.require(:jabvox_response_bot_seat).permit(:name_jabvox, :prompt_jabvox, :active_jabvox)
  end
end
