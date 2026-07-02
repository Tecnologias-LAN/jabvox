class Api::V1::Accounts::Jabvox::DataExport::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled
  before_action :ensure_admin

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_data_export')

    render json: { error: 'El módulo de Exportación de Datos no está habilitado para esta cuenta' },
           status: :forbidden
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar la exportación de datos' },
           status: :forbidden
  end
end
