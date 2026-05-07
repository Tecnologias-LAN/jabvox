class SuperAdmin::JabvoxResponseBotRolesController < SuperAdmin::ApplicationController
  before_action :set_role, only: [:edit, :update, :destroy]

  def index
    @roles = JabvoxResponseBotRole.ordered
  end

  def new
    @role = JabvoxResponseBotRole.new
  end

  def edit; end

  def create
    @role = JabvoxResponseBotRole.new(role_params)
    if @role.save
      redirect_to super_admin_jabvox_response_bot_roles_path, notice: 'Rol created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @role.update(role_params)
      redirect_to super_admin_jabvox_response_bot_roles_path, notice: 'Rol updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @role.destroy!
    redirect_to super_admin_jabvox_response_bot_roles_path, notice: 'Rol deleted.'
  end

  private

  def set_role
    @role = JabvoxResponseBotRole.find(params[:id])
  end

  def role_params
    params.require(:jabvox_response_bot_role).permit(:name_jabvox, :prompt_jabvox, :active_jabvox)
  end
end
