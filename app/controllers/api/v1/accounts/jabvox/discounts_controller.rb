class Api::V1::Accounts::Jabvox::DiscountsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_discount, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @discounts = policy_scope(Current.account.jabvox_discounts.ordered)
    @discounts = @discounts.active if params[:active].present?
  end

  def show; end

  def create
    @discount = Current.account.jabvox_discounts.new(discount_params)
    @discount.save!
  end

  def update
    @discount.update!(discount_params)
  end

  def destroy
    @discount.destroy!
    head :ok
  end

  private

  def fetch_discount
    @discount = Current.account.jabvox_discounts.find(params[:id])
  end

  def check_authorization
    authorize @discount || JabvoxDiscount
  end

  def discount_params
    params.require(:discount).permit(:name_jabvox, :description_jabvox, :percentage_jabvox, :active_jabvox)
  end
end
