class Api::V1::Accounts::Jabvox::Drive::DownloadsController < Api::V1::Accounts::Jabvox::BaseController
  # Streaming real (no bufferizado en memoria del proceso web) para el ramal stream.
  include ActionController::Live

  jabvox_feature 'jabvox_drive'

  # Tipos que se muestran EN LÍNEA (preview); el resto se fuerza como descarga.
  INLINE_PREVIEW = %r{\A(image/|application/pdf|audio/|video/)}
  # Tipos que NUNCA se sirven inline aunque matcheen INLINE_PREVIEW: pueden ejecutar
  # script en el navegador (XSS almacenado). Un SVG es image/svg+xml y matchearía
  # `image/`, pero puede contener <script>; se fuerza SIEMPRE como descarga.
  NEVER_INLINE = %r{\A(image/svg|text/html|application/xhtml|application/xml|text/xml|image/svg\+xml)}i
  # Extensiones de ejecutables/scripts que NUNCA se sirven inline y SIEMPRE por
  # streaming como attachment, pase lo que pase con el content_type. El Drive es
  # SOLO almacenamiento: estos archivos se guardan y descargan, nunca se "abren"
  # desde la app (la descarga como attachment + nosniff impide que el navegador
  # los ejecute o interprete).
  EXECUTABLE_EXTENSIONS = %w[
    exe bat cmd com msi msp scr pif ps1 psm1 vbs vbe js jse wsf wsh
    hta cpl jar app dmg pkg deb rpm sh bash zsh csh run bin elf out
    dll so dylib apk ipa gadget reg lnk inf
  ].freeze
  # MIME types ejecutables que, aunque llegaran, se fuerzan a descarga.
  EXECUTABLE_MIME = Regexp.union(
    %r{\Aapplication/x-(msdownload|msdos-program|executable|sh|shellscript|bat|dosexec|elf|mach-binary)\z}i,
    %r{\Aapplication/(vnd\.microsoft\.portable-executable|java-archive)\z}i
  ).freeze
  # Vida muy corta de la URL firmada: suficiente para la redirección del navegador.
  PRESIGN_TTL = 60

  before_action :fetch_file

  # Descarga segura. NUNCA expone la URL cruda y persistente de MinIO:
  #   - Por defecto redirige a una presigned de vida corta (TTL=60s) con el
  #     Content-Disposition correcto embebido.
  #   - Con ?stream=1 (o si falla el presign) hace streaming desde la app con
  #     cabeceras seguras (X-Content-Type-Options: nosniff).
  def show
    authorize @file, :download?

    # Auditoría: quién descargó qué (sin URL firmada ni contenido).
    Jabvox::Drive::AuditService.new(Current.account).log(
      action: 'download', actor: Current.user, auditable: @file,
      metadata: { filename: @file.filename, bytes: @file.byte_size }, request: request
    )

    # El contenido SIEMPRE se sirve por streaming desde la app (nunca se redirige al
    # navegador a la URL de MinIO) cuando:
    #   - se pide ?stream=1, o
    #   - el tipo es peligroso (SVG/HTML/XML: defensa anti-XSS almacenado), o
    #   - JABVOX_DRIVE_ALWAYS_STREAM=true (RECOMENDADO en producción: MinIO vive en
    #     red interna y NUNCA debe exponerse su host/URL al cliente).
    if always_stream? || ActiveModel::Type::Boolean.new.cast(params[:stream]) || dangerous_type?
      stream_file
    else
      redirect_to presigned_url, allow_other_host: true
    end
  rescue Jabvox::Drive::StorageService::ObjectNotFoundError
    # El objeto ya no existe en MinIO (fila huérfana). No es un fallo del servidor:
    # respondemos 404 claro en vez de un 503 engañoso.
    render json: { error: 'archivo no disponible' }, status: :not_found
  rescue Jabvox::Drive::StorageService::StorageUnavailableError
    render json: { error: 'almacenamiento no disponible, intenta más tarde' }, status: :service_unavailable
  end

  private

  # En producción MinIO está en red interna: servir siempre por la app evita exponer
  # su host al navegador y hace imposible interceptar URLs/credenciales de MinIO.
  def always_stream?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('JABVOX_DRIVE_ALWAYS_STREAM', false))
  end

  def fetch_file
    # policy_scope ya filtra a la cuenta activa y oculta no-visibles a los agentes.
    @file = policy_scope(Current.account.jabvox_drive_files).find(params[:id])
  end

  def storage
    @storage ||= Jabvox::Drive::StorageService.new(Current.account)
  end

  def bucket
    @file.overflow? ? Jabvox::Drive::StorageService::OVERFLOW : Jabvox::Drive::StorageService::PRIMARY
  end

  def disposition
    inline? ? 'inline' : 'attachment'
  end

  def inline?
    return false if dangerous_type?

    @file.content_type.to_s.match?(INLINE_PREVIEW)
  end

  def dangerous_type?
    @file.content_type.to_s.match?(NEVER_INLINE) ||
      @file.content_type.to_s.match?(EXECUTABLE_MIME) ||
      executable_extension?
  end

  # Un ejecutable/script por su extensión real (defensa aunque el MIME fuera
  # manipulado a algo "inofensivo"). El Drive es solo almacenamiento.
  def executable_extension?
    ext = File.extname(@file.filename.to_s).delete_prefix('.').downcase
    EXECUTABLE_EXTENSIONS.include?(ext)
  end

  def presigned_url
    storage.presigned_get(
      @file.object_key,
      bucket: bucket,
      expires_in: PRESIGN_TTL,
      disposition: disposition,
      filename: @file.filename
    )
  end

  # Streaming desde la app, sin exponer MinIO. Cabeceras endurecidas.
  #
  # Se verifica la existencia del objeto con head ANTES de abrir el stream: con
  # ActionController::Live, una vez escrita la cabecera no se puede cambiar el status,
  # así que un objeto inexistente debe detectarse aquí para poder devolver 404 (lo
  # convierte el rescue del #show). head también propaga StorageUnavailableError si
  # MinIO está caído (→ 503).
  def stream_file
    stream_opened = false
    # Verificación de existencia ANTES de abrir el stream (head propaga
    # ObjectNotFoundError → 404, o StorageUnavailableError → 503). Si no existe,
    # salimos sin tocar la respuesta para que el rescue del #show renderice el JSON.
    raise Jabvox::Drive::StorageService::ObjectNotFoundError if storage.head(@file.object_key, bucket: bucket).nil?

    set_stream_headers
    response.status = 200
    stream_opened = true
    storage.stream(@file.object_key, bucket: bucket) do |chunk|
      response.stream.write(chunk)
    end
  ensure
    response.stream.close if stream_opened
  end

  def set_stream_headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Type'] = @file.content_type.presence || 'application/octet-stream'
    response.headers['Content-Disposition'] =
      "#{disposition}; filename=\"#{safe_header_filename(@file.filename)}\""
    response.headers['Cache-Control'] = 'private, max-age=0, no-store'
  end

  def safe_header_filename(name)
    File.basename(name.to_s).tr('"', '').gsub(/[\u0000-\u001f]/, '')
  end
end
