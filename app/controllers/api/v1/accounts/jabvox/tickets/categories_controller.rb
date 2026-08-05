# Temas/categorías de tickets. Están CENTRALIZADOS en la cuenta gestora del helpdesk:
# cualquier usuario (desde cualquier cuenta cliente) los LEE para el formulario de
# registro, pero solo un manager (staff de la gestora) los crea/edita/elimina, y
# siempre sobre la cuenta gestora. Así todas las cuentas cliente comparten el mismo
# árbol de temas/subtemas.
class Api::V1::Accounts::Jabvox::Tickets::CategoriesController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  before_action :set_category, only: %i[update destroy]

  def index
    @categories = manager_account ? manager_account.jabvox_ticket_categories.ordered : JabvoxTicketCategory.none
  end

  def create
    authorize JabvoxTicketCategory, :create?
    @category = manager_account.jabvox_ticket_categories.create!(category_params)
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

  # Cuenta gestora del helpdesk (donde viven los temas). nil si no está configurada.
  def manager_account
    @manager_account ||= JabvoxTicketHelpdeskConfig.manager_account
  end

  # Solo categorías de la cuenta gestora: impide editar/borrar temas de otra cuenta
  # aunque se pase un id ajeno.
  def set_category
    raise ActiveRecord::RecordNotFound if manager_account.nil?

    @category = manager_account.jabvox_ticket_categories.find(params[:id])
  end

  def category_params
    params.permit(:name_jabvox, :category_type_jabvox, :color_jabvox, :description_jabvox,
                  :responsible_id, :sla_response_minutes_jabvox, :sla_resolution_minutes_jabvox,
                  :position_jabvox, :active_jabvox, :parent_id)
  end
end
