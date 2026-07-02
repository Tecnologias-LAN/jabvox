class Api::V1::Accounts::Jabvox::LeadImport::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled
  # Managing external DB connections is admin-only (credentials, network access).
  before_action :ensure_admin

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_lead_import')

    render json: { error: 'El módulo de Importación de Leads no está habilitado para esta cuenta' },
           status: :forbidden
  end

  # Admins keep full access (jabvox_can? bypasses for admins); a custom role may
  # also manage imports via jabvox_lead_import_manage.
  def ensure_admin
    return if jabvox_can?('jabvox_lead_import_manage')

    render json: { error: 'Solo los administradores pueden gestionar la importación de leads' },
           status: :forbidden
  end
end
