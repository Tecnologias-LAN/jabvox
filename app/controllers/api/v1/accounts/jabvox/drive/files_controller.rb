class Api::V1::Accounts::Jabvox::Drive::FilesController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_drive'

  PER_PAGE = 30

  before_action :fetch_file, only: [:show, :update, :destroy]
  # restore/purge actúan sobre archivos que YA están en la papelera (fuera del
  # policy_scope .kept), por eso usan un fetch que incluye los borrados de la cuenta.
  before_action :fetch_trashed_file, only: [:restore, :purge]

  # Listado con filtros: contact_id, folder_id, query (nombre), type (categoría),
  # created_after / created_before (fecha). Paginación por `page`.
  def index
    authorize JabvoxDriveFile
    files = policy_scope(Current.account.jabvox_drive_files)
    files = apply_filters(files)
    page = params[:page].to_i
    page = 1 if page < 1
    files = files.order(created_at: :desc).limit(PER_PAGE).offset((page - 1) * PER_PAGE)
    render json: { payload: files.map { |f| serialize_file(f) }, meta: { page: page, per_page: PER_PAGE } }
  end

  def show
    authorize @file
    render json: serialize_file(@file)
  end

  # create = subida multipart (campo :file) o bytes. Reserva cuota y rechaza si no cabe.
  def create
    authorize JabvoxDriveFile
    file = file_service.upload!(
      upload: params[:file],
      filename: params[:filename],
      content_type: params[:content_type],
      folder_id: params[:folder_id],
      contact_id: params[:contact_id],
      created_by: Current.user
    )
    audit('upload', file, filename: file.filename, bytes: file.byte_size, bucket: file.bucket)
    render json: serialize_file(file), status: :created
  end

  # update = renombrar y/o mover de carpeta.
  def update
    authorize @file
    if params.key?(:filename)
      old = @file.filename
      file_service.rename!(@file, filename: params[:filename])
      audit('rename', @file, from: old, to: @file.filename)
    end
    if params.key?(:folder_id)
      file_service.move!(@file, folder_id: params[:folder_id])
      audit('move', @file, folder_id: @file.folder_id)
    end
    render json: serialize_file(@file.reload)
  end

  # destroy = enviar a la PAPELERA (reversible; no libera espacio todavía).
  def destroy
    authorize @file
    file_service.destroy!(@file, actor: Current.user)
    audit('trash', @file, filename: @file.filename)
    head :ok
  end

  # trash (index) = listar lo que está en la papelera (solo admin).
  def trash
    authorize JabvoxDriveFile, :trash?
    page = [params[:page].to_i, 1].max
    files = policy_scope(Current.account.jabvox_drive_files).unscope(where: :deleted_at)
                                                            .in_trash.includes(:trashed_by).order(deleted_at: :desc)
                                                            .limit(PER_PAGE).offset((page - 1) * PER_PAGE)
    render json: { payload: files.map { |f| serialize_file(f) }, meta: { page: page, per_page: PER_PAGE } }
  end

  # restore = sacar de la papelera (vuelve a estar activo y a verse).
  def restore
    authorize @file, :restore?
    file_service.restore!(@file)
    audit('restore', @file, filename: @file.filename)
    render json: serialize_file(@file.reload)
  end

  # purge = ELIMINAR DEFINITIVAMENTE desde la papelera. Libera el espacio.
  def purge
    authorize @file, :purge?
    file_service.purge!(@file, actor: Current.user)
    audit('purge', @file, filename: @file.filename, bytes: @file.byte_size)
    head :ok
  end

  rescue_from Jabvox::Drive::FileService::FileTooLargeError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Jabvox::Drive::FileService::QuotaExceededError do |e|
    render json: { error: e.message }, status: :payment_required
  end

  rescue_from Jabvox::Drive::FileService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Jabvox::Drive::StorageService::StorageUnavailableError do |_e|
    render json: { error: 'almacenamiento no disponible, intenta más tarde' }, status: :service_unavailable
  end

  private

  def fetch_file
    @file = policy_scope(Current.account.jabvox_drive_files).find(params[:id])
  end

  # Para restore/purge: busca entre los archivos de la cuenta INCLUIDOS los que están
  # en la papelera (deleted_at != nil), pero NO los ya purgados. Scopeado a la cuenta.
  def fetch_trashed_file
    @file = Current.account.jabvox_drive_files.in_trash.find(params[:id])
  end

  def file_service
    @file_service ||= Jabvox::Drive::FileService.new(Current.account)
  end

  def audit(action, auditable, metadata = {})
    Jabvox::Drive::AuditService.new(Current.account)
                               .log(action: action, actor: Current.user, auditable: auditable,
                                    metadata: metadata, request: request)
  end

  def apply_filters(scope)
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    # Al BUSCAR o filtrar (texto/tipo/fecha) la búsqueda es GLOBAL en la cuenta: se
    # ignora la carpeta actual para encontrar archivos en cualquier contacto/bandeja.
    # Sin filtros, se navega carpeta por carpeta: dentro de una carpeta se muestran sus
    # archivos; en la RAÍZ (sin folder_id) solo los sueltos (folder_id NULL), NO todos
    # los de la cuenta — así los que están en subcarpetas no aparecen duplicados arriba.
    scope = scope.where(folder_id: params[:folder_id].presence) unless searching? || params[:contact_id].present?
    scope = filter_by_query(scope)
    scope = filter_by_type(scope, params[:type]) if params[:type].present?
    filter_by_date(scope)
  end

  # ¿Hay una búsqueda o filtro activo (que debe buscar en toda la cuenta)?
  def searching?
    params[:query].present? || params[:type].present? ||
      params[:created_after].present? || params[:created_before].present?
  end

  # Busca por nombre de ARCHIVO y también por nombre/teléfono/username del CONTACTO
  # (via su carpeta). Así "rojas" encuentra los archivos de "María Rojas" aunque el
  # archivo se llame "contrato.docx".
  def filter_by_query(scope)
    return scope if params[:query].blank?

    like = "%#{sanitize_like(params[:query])}%"
    contact_ids = Current.account.contacts
                         .where('name ILIKE ? OR phone_number ILIKE ? OR identifier ILIKE ?', like, like, like)
                         .limit(500).pluck(:id)
    scope.where('filename ILIKE ? OR jabvox_drive_files.contact_id IN (?)', like, contact_ids.presence || [-1])
  end

  def filter_by_date(scope)
    scope = scope.where('created_at >= ?', parse_date(params[:created_after])) if params[:created_after].present?
    scope = scope.where('created_at <= ?', parse_date(params[:created_before])) if params[:created_before].present?
    scope
  end

  # Filtra por categoría (image/video/audio/document) usando el content_type.
  def filter_by_type(scope, type)
    case type.to_s
    when 'image' then scope.where('content_type ILIKE ?', 'image/%')
    when 'video' then scope.where('content_type ILIKE ?', 'video/%')
    when 'audio' then scope.where('content_type ILIKE ?', 'audio/%')
    when 'document'
      scope.where("content_type NOT ILIKE 'image/%' AND content_type NOT ILIKE 'video/%' " \
                  "AND content_type NOT ILIKE 'audio/%' OR content_type IS NULL")
    else scope
    end
  end

  def sanitize_like(value)
    value.to_s.gsub(/[%_\\]/) { |c| "\\#{c}" }
  end

  def parse_date(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def serialize_file(file)
    {
      id: file.id,
      filename: file.filename,
      content_type: file.content_type,
      byte_size: file.byte_size,
      category: file.category,
      status: file.status,
      bucket: file.bucket,
      folder_id: file.folder_id,
      contact_id: file.contact_id,
      message_id: file.message_id,
      conversation_id: file.conversation_id,
      created_by_id: file.created_by_id,
      created_at: file.created_at,
      download_url: download_path_for(file)
    }.merge(trash_fields(file))
  end

  # Campos de papelera (derivados del server, no manipulables por el cliente).
  def trash_fields(file)
    {
      in_trash: file.in_trash?,
      deleted_at: file.deleted_at,
      trashed_by_name: file.trashed_by&.name,
      # Cuándo se purgará automáticamente (para mostrar "se elimina en X días").
      purge_at: file.deleted_at && (file.deleted_at + JabvoxDriveFile::TRASH_RETENTION_DAYS.days)
    }
  end

  def download_path_for(file)
    "/api/v1/accounts/#{Current.account.id}/jabvox/drive/files/#{file.id}/download"
  end
end
