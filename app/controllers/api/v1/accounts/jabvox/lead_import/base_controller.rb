class Api::V1::Accounts::Jabvox::LeadImport::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled
  # Managing external DB connections is admin-only (credentials, network access).
  before_action :ensure_admin

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_lead_import')

    render json: { error: 'El módulo de Importación de Leads no está habilitado para esta cuenta' },
           status: :forbidden
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar la importación de leads' },
           status: :forbidden
  end
end
