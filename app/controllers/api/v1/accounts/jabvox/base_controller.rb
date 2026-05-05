class Api::V1::Accounts::Jabvox::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_kanban')

    render json: { error: 'Jabvox Kanban feature is not enabled for this account' }, status: :forbidden
  end
end
