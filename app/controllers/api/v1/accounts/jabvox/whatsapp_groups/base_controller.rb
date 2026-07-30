class Api::V1::Accounts::Jabvox::WhatsappGroups::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_whatsapp_groups')

    render json: { error: 'El módulo de Grupos de WhatsApp no está habilitado para esta cuenta' },
           status: :forbidden
  end

  # Managing groups is admin-gated, or a custom role granting jabvox_whatsapp_groups_manage.
  def ensure_admin
    return if jabvox_can?('jabvox_whatsapp_groups_manage')

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
