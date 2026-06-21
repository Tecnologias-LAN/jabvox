class Api::V1::Accounts::Jabvox::QuickButtonsController < Api::V1::Accounts::BaseController
  before_action :check_customization_enabled
  before_action :set_button, only: [:update, :destroy]

  def index
    @buttons = Current.account.jabvox_quick_buttons.ordered
    render json: @buttons.map { |b| button_json(b) }
  end

  def create
    @button = Current.account.jabvox_quick_buttons.build(button_params)
    @button.save!
    render json: button_json(@button), status: :created
  end

  def update
    @button.update!(button_params)
    render json: button_json(@button)
  end

  def destroy
    @button.destroy!
    head :no_content
  end

  private

  def check_customization_enabled
    return if Current.account.jabvox_customization_enabled_jabvox?

    render json: { error: 'Customization module not enabled' }, status: :forbidden
  end

  def set_button
    @button = Current.account.jabvox_quick_buttons.find(params[:id])
  end

  def button_params
    params.require(:button).permit(:name_jabvox, :url_jabvox, :color_jabvox, :active_jabvox, :position_jabvox)
  end

  def button_json(button)
    {
      id: button.id,
      name_jabvox: button.name_jabvox,
      url_jabvox: button.url_jabvox,
      color_jabvox: button.color_jabvox,
      active_jabvox: button.active_jabvox,
      position_jabvox: button.position_jabvox
    }
  end
end
