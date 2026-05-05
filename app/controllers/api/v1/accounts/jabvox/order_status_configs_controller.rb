class Api::V1::Accounts::Jabvox::OrderStatusConfigsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_status_config, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @status_configs = policy_scope(Current.account.jabvox_order_status_configs.ordered)
  end

  def show; end

  def create
    @status_config = Current.account.jabvox_order_status_configs.new(status_config_params)
    @status_config.save!
  end

  def update
    @status_config.update!(status_config_params)
  end

  def destroy
    @status_config.destroy!
    head :ok
  end

  private

  def fetch_status_config
    @status_config = Current.account.jabvox_order_status_configs.find(params[:id])
  end

  def check_authorization
    authorize @status_config || JabvoxOrderStatusConfig
  end

  def status_config_params
    params.require(:status_config).permit(:key_jabvox, :label_jabvox, :sort_order_jabvox, :color_jabvox)
  end
end
