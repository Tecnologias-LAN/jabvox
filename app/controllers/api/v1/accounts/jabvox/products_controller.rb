class Api::V1::Accounts::Jabvox::ProductsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_product, only: [:show, :update, :destroy]
  before_action :check_authorization

  def import
    config = Current.account.jabvox_integration_config
    raise 'No hay integración contable configurada. Configura el email y token en la pestaña Integración.' unless config&.integration_email_jabvox.present?

    result = Jabvox::AlegraImportService.new(account: Current.account, config: config).import!
    render json: {
      message: "Importación completada: #{result[:created]} creados, #{result[:updated]} actualizados.",
      created: result[:created],
      updated: result[:updated],
      errors: result[:errors]
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    @products = policy_scope(Current.account.jabvox_products.ordered
                  .includes(:jabvox_currency, :jabvox_item_type, :jabvox_unit_of_measure))
    @products = @products.active if params[:active].present?
  end

  def show; end

  def create
    @product = Current.account.jabvox_products.new(product_params)
    @product.save!
  end

  def update
    @product.update!(product_params)
  end

  def destroy
    @product.destroy!
    head :ok
  end

  private

  def fetch_product
    @product = Current.account.jabvox_products.find(params[:id])
  end

  def check_authorization
    authorize @product || JabvoxProduct
  end

  def product_params
    params.require(:product).permit(
      :name_jabvox, :description_jabvox, :price_jabvox, :base_price_jabvox,
      :tax_percentage_jabvox, :total_price_jabvox, :active_jabvox,
      :product_type_jabvox, :integration_item_id_jabvox,
      :jabvox_currency_id, :jabvox_item_type_id, :jabvox_unit_of_measure_id
    )
  end
end
