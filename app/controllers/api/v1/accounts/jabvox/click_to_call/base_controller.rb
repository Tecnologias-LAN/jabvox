class Api::V1::Accounts::Jabvox::ClickToCall::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_click_to_call')

    render json: { error: 'Jabvox Click to Call feature is not enabled for this account' }, status: :forbidden
  end
end
