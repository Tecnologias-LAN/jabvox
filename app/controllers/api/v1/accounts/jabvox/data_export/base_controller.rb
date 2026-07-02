class Api::V1::Accounts::Jabvox::DataExport::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled
  before_action :ensure_admin

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_data_export')

    render json: { error: 'El módulo de Exportación de Datos no está habilitado para esta cuenta' },
           status: :forbidden
  end

  # Admins keep full access (jabvox_can? bypasses for admins); a custom role may
  # also manage exports via jabvox_data_export_manage.
  def ensure_admin
    return if jabvox_can?('jabvox_data_export_manage')

    render json: { error: 'Solo los administradores pueden gestionar la exportación de datos' },
           status: :forbidden
  end
end
