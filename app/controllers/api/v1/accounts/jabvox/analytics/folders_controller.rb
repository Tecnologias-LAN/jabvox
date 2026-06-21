class Api::V1::Accounts::Jabvox::Analytics::FoldersController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_folder, only: %i[show update destroy]

  def index
    render json: scoped.ordered.map { |f| serialize(f) }
  end

  def show
    render json: serialize(@folder)
  end

  def create
    authorize!(:create)
    folder = scoped.new(folder_params)
    folder.account = Current.account
    folder.created_by = current_user
    if folder.save
      render json: serialize(folder), status: :created
    else
      render json: { errors: folder.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    authorize!(:create)
    if @folder.update(folder_params)
      render json: serialize(@folder)
    else
      render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    authorize!(:create)
    @folder.destroy!
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_analytics_folders
  end

  def set_folder
    @folder = scoped.find(params[:id])
  end

  def folder_params
    params.require(:folder).permit(:name_jabvox, :parent_id, :position_jabvox)
  end

  def serialize(folder)
    {
      id: folder.id,
      name_jabvox: folder.name_jabvox,
      parent_id: folder.parent_id,
      position_jabvox: folder.position_jabvox,
      created_at: folder.created_at
    }
  end
end
