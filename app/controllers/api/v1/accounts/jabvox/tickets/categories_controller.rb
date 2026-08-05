# Categorías/temas de tickets. Cualquiera las lista (para el formulario de registro);
# solo un manager (staff) las crea/edita/elimina (validado por la policy).
class Api::V1::Accounts::Jabvox::Tickets::CategoriesController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  before_action :set_category, only: %i[update destroy]

  def index
    @categories = Current.account.jabvox_ticket_categories.ordered
  end

  def create
    authorize JabvoxTicketCategory, :create?
    @category = Current.account.jabvox_ticket_categories.create!(category_params)
    render :show, status: :created
  end

  def update
    authorize @category, :update?
    @category.update!(category_params)
    render :show
  end

  def destroy
    authorize @category, :destroy?
    @category.destroy!
    head :no_content
  end

  private

  def set_category
    @category = Current.account.jabvox_ticket_categories.find(params[:id])
  end

  def category_params
    params.permit(:name_jabvox, :category_type_jabvox, :color_jabvox, :description_jabvox,
                  :responsible_id, :sla_response_minutes_jabvox, :sla_resolution_minutes_jabvox,
                  :position_jabvox, :active_jabvox)
  end
end
