class Api::V1::Accounts::Jabvox::IntegrationConfigsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization

  def show
    @config = Current.account.jabvox_integration_config || JabvoxIntegrationConfig.new
  end

  def update
    @config = Current.account.jabvox_integration_config ||
              Current.account.build_jabvox_integration_config
    @config.update!(config_params)
    render :show
  end

  def destroy
    config = Current.account.jabvox_integration_config
    config&.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize :jabvox_integration_config
  end

  def config_params
    p = params.require(:config).permit(
      :integration_type_jabvox, :integration_email_jabvox, :integration_token_jabvox,
      :company_name_jabvox, :company_nit_jabvox, :company_address_jabvox,
      :company_phone_jabvox, :company_email_jabvox, :company_website_jabvox,
      :company_logo_jabvox
    )
    p.delete(:integration_token_jabvox) if p[:integration_token_jabvox].blank?
    p
  end
end
