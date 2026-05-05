class Api::V1::Accounts::Jabvox::TaxRatesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_tax_rate, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @tax_rates = policy_scope(Current.account.jabvox_tax_rates.ordered)
  end

  def show; end

  def create
    @tax_rate = Current.account.jabvox_tax_rates.new(tax_rate_params)
    @tax_rate.save!
  end

  def update
    @tax_rate.update!(tax_rate_params)
  end

  def destroy
    @tax_rate.destroy!
    head :ok
  end

  private

  def fetch_tax_rate
    @tax_rate = Current.account.jabvox_tax_rates.find(params[:id])
  end

  def check_authorization
    authorize @tax_rate || JabvoxTaxRate
  end

  def tax_rate_params
    params.require(:tax_rate).permit(:name_jabvox, :percentage_jabvox, :active_jabvox)
  end
end
