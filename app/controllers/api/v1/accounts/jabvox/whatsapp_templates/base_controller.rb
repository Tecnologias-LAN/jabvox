class Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_can_manage

  private

  def ensure_can_manage
    return if Current.account_user&.administrator?

    perm = Current.account.jabvox_whatsapp_template_permissions.find_by(user_id: Current.user.id)
    return if perm&.can_manage?

    render json: { error: 'Acceso denegado' }, status: :forbidden
  end

  def manager
    @manager ||= Jabvox::WhatsappTemplatesManager.new(Current.account, user: Current.user)
  end
end
