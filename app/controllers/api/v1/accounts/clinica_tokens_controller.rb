class Api::V1::Accounts::ClinicaTokensController < Api::V1::Accounts::BaseController
  def create
    return render json: { error: 'user_authentication_required' }, status: :unauthorized unless Current.user.is_a?(User)

    token = Auth::ClinicaJwtIssuer.issue(user: Current.user, account: Current.account)
    render json: { token: token }
  end
end
