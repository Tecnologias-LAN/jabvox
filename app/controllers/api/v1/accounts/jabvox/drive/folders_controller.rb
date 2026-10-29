class Api::V1::Accounts::Jabvox::Drive::FoldersController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_drive'

  before_action :fetch_folder, only: [:show, :update, :destroy]

  def index
    authorize JabvoxDriveFolder
    folders = policy_scope(Current.account.jabvox_drive_folders)
    if params[:query].present?
      # Búsqueda GLOBAL por nombre (en toda la cuenta, no solo el nivel actual).
      like = "%#{sanitize_like(params[:query])}%"
      folders = folders.where('name ILIKE ?', like)
    else
      # Navegación normal: carpetas hijas del nivel actual.
      folders = folders.where(parent_id: params[:parent_id].presence)
    end
    folders = folders.order(:name)
    render json: { payload: folders.map { |f| serialize_folder(f) } }
  end

  def show
    authorize @folder
    render json: serialize_folder(@folder)
  end

  def create
    authorize JabvoxDriveFolder
    folder = folder_service.create!(
      name: params[:name],
      parent_id: params[:parent_id],
      created_by: Current.user
    )
    audit('create_folder', folder, name: folder.name, parent_id: folder.parent_id)
    render json: serialize_folder(folder), status: :created
  end

  # update = renombrar y/o mover.
  def update
    authorize @folder
    if params.key?(:name)
      old = @folder.name
      folder_service.rename!(@folder, name: params[:name])
      audit('rename_folder', @folder, from: old, to: @folder.name)
    end
    if params.key?(:parent_id)
      folder_service.move!(@folder, parent_id: params[:parent_id])
      audit('move_folder', @folder, parent_id: @folder.parent_id)
    end
    render json: serialize_folder(@folder.reload)
  end

  def destroy
    authorize @folder
    # Las carpetas de SISTEMA (contactos/ y las de cada contacto/bandeja) NO se pueden
    # eliminar: son parte de la estructura canónica. Sus ARCHIVOS sí se pueden borrar,
    # y otras carpetas creadas por el usuario (aunque se llamen igual) también.
    if @folder.system_folder?
      return render json: { error: 'Esta carpeta del sistema no se puede eliminar' },
                    status: :unprocessable_entity
    end

    folder_service.destroy!(@folder)
    audit('delete_folder', @folder, name: @folder.name)
    head :ok
  end

  rescue_from Jabvox::Drive::FolderService::SystemFolderError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Jabvox::Drive::FolderService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Escapa los comodines de LIKE para que la búsqueda sea literal (anti-inyección).
  def sanitize_like(value)
    value.to_s.gsub(/[%_\\]/) { |c| "\\#{c}" }
  end

  def fetch_folder
    @folder = Current.account.jabvox_drive_folders.find(params[:id])
  end

  def folder_service
    @folder_service ||= Jabvox::Drive::FolderService.new(Current.account)
  end

  def audit(action, auditable, metadata = {})
    Jabvox::Drive::AuditService.new(Current.account)
                               .log(action: action, actor: Current.user, auditable: auditable,
                                    metadata: metadata, request: request)
  end

  def serialize_folder(folder)
    {
      id: folder.id,
      name: folder.name,
      path: folder.path,
      parent_id: folder.parent_id,
      contact_id: folder.contact_id,
      system_folder: folder.system_folder,
      created_at: folder.created_at
    }
  end
end
