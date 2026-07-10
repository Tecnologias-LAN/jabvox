class Api::V1::Accounts::Jabvox::SmtpConfigsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
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
    error = validate_config_for_test
    return render json: { error: error }, status: :unprocessable_entity if error

    from = @config.from_email
    Mail.new do
      from    "#{@config.from_name.presence || 'Jabvox'} <#{from}>"
      to      from
      subject 'Jabvox SMTP Test'
      body    'SMTP configuration is working correctly.'
    end.tap { |m| m.delivery_method(:smtp, @config.delivery_settings) }.deliver!

    @config.update!(verified: true)
    render json: { success: true }
  rescue StandardError => e
    @config&.update(verified: false)
    render json: { error: friendly_smtp_error(e) }, status: :unprocessable_entity
  end

  private

  # Everything the SMTP handshake needs must be present before we try, so the
  # user gets a precise message instead of a cryptic connection error.
  def validate_config_for_test
    return 'Configura la dirección del servidor SMTP.' if @config&.address.blank?
    return 'Configura el puerto SMTP.' if @config.port.blank?
    return 'Configura el correo remitente (De).' if @config.from_email.blank?
    return 'La contraseña es obligatoria cuando defines un usuario.' if @config.username.present? && @config.password.blank?

    nil
  end

  # Turns the raw Net::SMTP / OpenSSL / socket exceptions into a clear Spanish
  # message pointing at the real cause.
  def friendly_smtp_error(exception)
    msg = exception.message.to_s
    case exception
    when Net::SMTPAuthenticationError
      'Autenticación rechazada: revisa el usuario y la contraseña.'
    when Net::OpenTimeout, Errno::ETIMEDOUT
      'Tiempo de espera agotado: revisa la dirección y el puerto, o si un firewall bloquea la conexión.'
    when Errno::ECONNREFUSED
      'Conexión rechazada: la dirección o el puerto del servidor no son correctos.'
    when SocketError
      'No se pudo resolver el servidor: revisa la dirección SMTP.'
    when OpenSSL::SSL::SSLError
      'Error de seguridad TLS/SSL: revisa las opciones STARTTLS y SSL/TLS y el puerto (587 STARTTLS, 465 SSL).'
    when Net::SMTPServerBusy, Net::SMTPFatalError, Net::SMTPSyntaxError, Net::SMTPUnknownError
      "El servidor SMTP rechazó el envío: #{msg}"
    else
      msg.presence || 'No se pudo conectar al servidor SMTP.'
    end
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_email_manage')
  end

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
