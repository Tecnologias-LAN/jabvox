class Api::V1::Accounts::Jabvox::FormConfigsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :check_feature_enabled
  before_action :set_config, only: [:show, :update]

  def show; end

  def update
    @config.update!(config_params)
    render :show
  end

  private

  def set_config
    @config = Current.account.jabvox_form_config || Current.account.build_jabvox_form_config
    @config.save! unless @config.persisted?
  end

  def check_authorization(*)
    authorize(JabvoxFormConfig)
  end

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_forms')

    render json: { error: 'Jabvox Forms feature is not enabled for this account' }, status: :forbidden
  end

  def config_params
    params.require(:form_config).permit(:base_url_jabvox)
  end
end
