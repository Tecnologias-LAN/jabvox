class Api::V1::Accounts::Jabvox::ClickToCall::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled
  before_action :ensure_module_permission

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_click_to_call')

    render json: { error: 'Jabvox Click to Call feature is not enabled for this account' }, status: :forbidden
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize!('jabvox_click_to_call_use')
  end
end
