class Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_bulk_whatsapp')

    render json: { error: 'El módulo de Envío Masivo de WhatsApp no está habilitado para esta cuenta' },
           status: :forbidden
  end

  # Admins keep full access (jabvox_can? bypasses for admins); a custom role may
  # also send via jabvox_bulk_whatsapp_send.
  def ensure_admin
    return if jabvox_can?('jabvox_bulk_whatsapp_send')

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
