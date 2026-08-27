# frozen_string_literal: true

# Panel Super Admin: gestión de la credencial SIP del softphone + estado en vivo.
# La EXTENSIÓN vive en VoIP (jabvox_user_extensions); este panel la muestra y la deja
# editar también aquí (escribe en la misma tabla), para no ir a VoIP de la cuenta.
class SuperAdmin::JabvoxSoftphoneExtensionsController < SuperAdmin::ApplicationController
  # Estado en vivo de todas las cuentas con softphone + historial de llamadas filtrable.
  def status
    @accounts_status = Account
                       .where(jabvox_softphone_enabled_jabvox: true)
                       .order(:name)
                       .map { |account| [account, Jabvox::Softphone::StatusService.new(account).call] }

    load_call_logs
    @filter_accounts = Account.where(jabvox_softphone_enabled_jabvox: true).order(:name)
  end

  def create
    resource = resource_class.new(resource_params)
    if resource.save
      sync_voip_extension(resource)
      redirect_to [namespace, resource], notice: translate_with_resource('create.success')
    else
      render :new, locals: { page: Administrate::Page::Form.new(dashboard, resource) }
    end
  end

  def update
    if requested_resource.update(resource_params)
      sync_voip_extension(requested_resource)
      redirect_to [namespace, requested_resource], notice: translate_with_resource('update.success')
    else
      render :edit, locals: { page: Administrate::Page::Form.new(dashboard, requested_resource) }
    end
  end

  private

  # Historial de llamadas del softphone (todas las cuentas), con filtros del panel:
  # cuenta, extensión, estado, dirección y rango de fechas. Paginado simple.
  def load_call_logs
    scope = filtered_logs
    @page = [params[:page].to_i, 1].max
    @per_page = 50
    @total_logs = scope.count
    @call_logs = scope.limit(@per_page).offset((@page - 1) * @per_page)
  end

  def filtered_logs
    scope = JabvoxSoftphoneCallLog.includes(:account, :user).order(started_at: :desc)
    { account_id: :account_id, extension: :extension,
      status: :status, direction: :direction }.each do |param, col|
      scope = scope.where(col => params[param]) if params[param].present?
    end
    filter_by_date(scope)
  end

  def filter_by_date(scope)
    scope = scope.where(started_at: Time.zone.parse(params[:from]).beginning_of_day..) if params[:from].present?
    scope = scope.where(started_at: ..Time.zone.parse(params[:to]).end_of_day) if params[:to].present?
    scope
  rescue ArgumentError
    scope # fecha inválida: se ignora el filtro
  end

  # El campo "extension" del form no es columna del modelo (vive en VoIP): se descarta aquí
  # y se sincroniza aparte en sync_voip_extension. Un secreto vacío al EDITAR no lo cambia.
  def resource_params
    permitted = params.require(:jabvox_softphone_extension)
                      .permit(:account_id, :user_id, :sip_secret, :webrtc_enabled)
    permitted.delete(:sip_secret) if permitted[:sip_secret].blank? && params[:action] == 'update'
    permitted
  end

  # Escribe la extensión capturada en el form en jabvox_user_extensions (fuente de VoIP).
  def sync_voip_extension(resource)
    ext = params.dig(:jabvox_softphone_extension, :extension).to_s.strip
    return if ext.blank?

    ve = JabvoxUserExtension.find_or_initialize_by(
      account_id: resource.account_id, user_id: resource.user_id
    )
    ve.update(extension_jabvox: ext)
  end
end
