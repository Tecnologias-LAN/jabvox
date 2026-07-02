class Api::V1::Accounts::Jabvox::SaldoConfigsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :authorize_config
  before_action :check_feature_enabled
  before_action :ensure_module_permission

  def show
    @config = Current.account.jabvox_saldo_config || Current.account.build_jabvox_saldo_config
  end

  def update
    @config = Current.account.jabvox_saldo_config || Current.account.build_jabvox_saldo_config

    attrs = config_params.to_h
    attrs.delete('api_secret_jabvox') if attrs['api_secret_jabvox'].blank?

    @config.update!(attrs)
    render :show
  end

  def status
    config = Current.account.jabvox_saldo_config
    @status = Jabvox::SaldoService.new(config).fetch_balance

    render json: @status
  end

  private

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!('jabvox_saldo_manage')
  end

  def authorize_config
    authorize :jabvox_saldo_config
  end

  def config_params
    params.require(:config).permit(
      :name_jabvox,
      :base_url_jabvox,
      :api_key_jabvox,
      :api_secret_jabvox,
      :saldo_username_jabvox,
      :proxy_url_jabvox,
      :use_proxy_jabvox,
      :is_active_jabvox
    )
  end

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_saldo')

    render json: { error: 'Jabvox Saldo feature is not enabled for this account' }, status: :forbidden
  end
end
