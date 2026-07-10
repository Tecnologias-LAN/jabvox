class Api::V1::Accounts::Jabvox::CurrenciesController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_products'
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :fetch_currency, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @currencies = policy_scope(Current.account.jabvox_currencies.ordered)
  end

  def show; end

  def create
    @currency = Current.account.jabvox_currencies.new(currency_params)
    @currency.save!
  end

  def update
    @currency.update!(currency_params)
  end

  def destroy
    @currency.destroy!
    head :ok
  end

  private

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_products_manage')
  end

  def fetch_currency
    @currency = Current.account.jabvox_currencies.find(params[:id])
  end

  def check_authorization
    authorize @currency || JabvoxCurrency
  end

  def currency_params
    params.require(:currency).permit(:symbol_jabvox, :name_jabvox, :active_jabvox)
  end
end
