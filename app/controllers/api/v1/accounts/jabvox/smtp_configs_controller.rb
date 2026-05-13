class Api::V1::Accounts::Jabvox::SmtpConfigsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :set_config, only: [:show, :update, :destroy, :test]

  def show
    @config = Current.account.jabvox_smtp_config || JabvoxSmtpConfig.new(account: Current.account)
  end

  def create
    @config = Current.account.create_jabvox_smtp_config!(smtp_params)
    render :show, status: :created
  end

  def update
    @config.update!(smtp_params)
    render :show
  end

  def destroy
    @config.destroy!
    head :no_content
  end

  def test
    return render json: { error: 'SMTP not configured' }, status: :unprocessable_entity unless @config&.address.present?

    Mail.new do
      from    "#{@config.from_name} <#{@config.from_email}>"
      to      @config.from_email
      subject 'Jabvox SMTP Test'
      body    'SMTP configuration is working correctly.'
    end.tap { |m| m.delivery_method(:smtp, @config.delivery_settings) }.deliver!

    @config.update!(verified: true)
    render json: { success: true }
  rescue StandardError => e
    @config&.update(verified: false)
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_config
    @config = Current.account.jabvox_smtp_config
  end

  def smtp_params
    params.require(:smtp_config).permit(
      :from_name, :from_email, :address, :port, :domain,
      :username, :password, :authentication,
      :enable_starttls_auto, :enable_ssl_tls,
      :calendar_reminders_enabled, calendar_reminder_minutes: []
    )
  end
end
