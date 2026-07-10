class Api::V1::Accounts::Jabvox::UnitsOfMeasureController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :fetch_unit, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @units = policy_scope(Current.account.jabvox_units_of_measure.ordered)
  end

  def show; end

  def create
    @unit = Current.account.jabvox_units_of_measure.new(unit_params)
    @unit.save!
  end

  def update
    @unit.update!(unit_params)
  end

  def destroy
    @unit.destroy!
    head :ok
  end

  private

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_products_manage')
  end

  def fetch_unit
    @unit = Current.account.jabvox_units_of_measure.find(params[:id])
  end

  def check_authorization
    authorize @unit || JabvoxUnitOfMeasure
  end

  def unit_params
    params.require(:unit).permit(:name_jabvox, :abbreviation_jabvox, :active_jabvox)
  end
end
