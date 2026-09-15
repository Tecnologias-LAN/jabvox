# frozen_string_literal: true

# Carga masiva de leads desde el portal de afiliados.
#
# El archivo NO se procesa dentro del request: se guarda y se encola en la cola
# aislada de importaciones (jabvox_lead_import). Así varios afiliados de varias
# cuentas subiendo a la vez no bloquean hilos de Puma ni se saturan entre sí; el
# portal consulta el avance con `show`.
#
# A diferencia del import del dashboard, aquí NO existe la opción de actualizar
# un lead existente: si el teléfono o el correo ya existen, la fila se omite y se
# cuenta como duplicada. Al terminar, el resumen dice cuántos se montaron y
# cuántos no.
class Api::V1::Jabvox::AffiliatePortal::ImportsController < Api::V1::Jabvox::AffiliatePortal::BaseController
  MAX_ROWS = 5_000
  # Tope de tamaño del archivo: el portal es un endpoint autenticado por JWT de
  # afiliado, no un panel de administración — no debe aceptar subidas grandes.
  MAX_FILE_BYTES = 5.megabytes

  # GET /imports/:id — avance de una importación en curso, o su resumen final.
  def show
    import = scoped_imports.find_by(id: params[:id])
    return render_error('not_found', :not_found) unless import

    render json: serialize_import(import)
  end

  # POST /api/v1/jabvox/affiliate_portal/imports
  # Params: file (CSV con columnas name, email, phone), country (ISO, obligatorio)
  def create
    rejection = rejection_reason
    return render_rejection(rejection) if rejection

    import = create_import!(@row_count)
    Jabvox::LeadImport::AffiliateCsvJob.perform_later(import.id)
    render json: serialize_import(import), status: :accepted
  end

  private

  # Primer motivo por el que la subida no se acepta, o nil si todo está bien.
  # Deja @row_count listo cuando el archivo es válido.
  def rejection_reason
    invalid_request_reason || invalid_content_reason
  end

  # Motivos que se ven sin leer el archivo.
  def invalid_request_reason
    return 'file_missing' if params[:file].blank?
    return 'file_too_large' if params[:file].size.to_i > MAX_FILE_BYTES
    return 'country_required' unless Jabvox::LeadIdentityService.valid_country?(params[:country])

    # Un afiliado no puede tener dos cargas en curso: evita que una cuenta
    # acapare el worker y que dos archivos solapados generen duplicados.
    'import_in_progress' if import_in_progress?
  end

  # Motivos que dependen del contenido del CSV. Deja @row_count listo.
  def invalid_content_reason
    @row_count = count_rows(params[:file])
    return 'file_empty' if @row_count.nil? || @row_count.zero?

    'too_many_rows' if @row_count > MAX_ROWS
  end

  def render_rejection(code)
    return render(json: { error: code, max: MAX_ROWS }, status: :unprocessable_entity) if code == 'too_many_rows'

    render_error(code)
  end

  # Siempre acotado al afiliado autenticado: nunca puede consultar la
  # importación de otro afiliado, ni siquiera dentro de su misma cuenta.
  def scoped_imports
    @current_account.jabvox_affiliate_imports.where(jabvox_affiliate: @current_affiliate)
  end

  def import_in_progress?
    scoped_imports.status_processing.exists?
  end

  def create_import!(row_count)
    import = scoped_imports.new(
      jabvox_affiliate: @current_affiliate,
      import_type: :csv,
      status: :processing,
      filename: params[:file].original_filename,
      rows_total: row_count,
      country_jabvox: params[:country].to_s.strip.upcase,
      campaign_name_jabvox: params[:campaign].to_s.strip.presence
    )
    import.source_file.attach(params[:file])
    import.save!
    import
  end

  # Solo cuenta filas para validar el tamaño; el contenido lo procesa el job.
  # Devuelve nil si el CSV no se puede leer.
  def count_rows(file)
    require 'csv'
    content = file.read.force_encoding('UTF-8')
    content = content.scrub('') unless content.valid_encoding?
    file.rewind
    CSV.parse(content, headers: true, skip_blanks: true).size
  rescue CSV::MalformedCSVError
    nil
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code }, status: status
  end

  def serialize_import(import)
    {
      id: import.id,
      status: import.status,
      filename: import.filename,
      rows_total: import.rows_total,
      rows_ok: import.rows_ok,
      rows_failed: import.rows_failed,
      rows_duplicated: import.rows_duplicated,
      rows_processed: import.rows_processed,
      progress: import.progress_percent,
      error: import.error_message,
      created_at: import.created_at,
      completed_at: import.completed_at
    }
  end
end
