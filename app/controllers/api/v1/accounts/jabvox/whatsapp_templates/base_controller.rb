class Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :ensure_can_manage

  private

  # Admins always pass (handled by the concern); other users need the
  # 'jabvox_whatsapp_templates_manage' capability on their custom role.
  def ensure_can_manage
    return if jabvox_can?('jabvox_whatsapp_templates_manage')

    render json: { error: 'Acceso denegado' }, status: :forbidden
  end

  def manager
    @manager ||= Jabvox::WhatsappTemplatesManager.new(Current.account, user: Current.user)
  end
end
