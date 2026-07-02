class Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_bulk_whatsapp')

    render json: { error: 'El módulo de Envío Masivo de WhatsApp no está habilitado para esta cuenta' },
           status: :forbidden
  end

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden gestionar esta sección' }, status: :forbidden
  end
end
