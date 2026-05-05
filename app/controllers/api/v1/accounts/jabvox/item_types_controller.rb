class Api::V1::Accounts::Jabvox::ItemTypesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_item_type, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @item_types = policy_scope(Current.account.jabvox_item_types.ordered)
  end

  def show; end

  def create
    @item_type = Current.account.jabvox_item_types.new(item_type_params)
    @item_type.save!
  end

  def update
    @item_type.update!(item_type_params)
  end

  def destroy
    @item_type.destroy!
    head :ok
  end

  private

  def fetch_item_type
    @item_type = Current.account.jabvox_item_types.find(params[:id])
  end

  def check_authorization
    authorize @item_type || JabvoxItemType
  end

  def item_type_params
    params.require(:item_type).permit(:name_jabvox, :active_jabvox)
  end
end
