class Api::V1::Accounts::Jabvox::EmailsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_email'
  include JabvoxPermissions

  before_action :ensure_module_permission

  # Cabeceras: solo se acepta UNA dirección sin CR/LF, así que nadie puede
  # inyectar Bcc:/Cc: ni colar destinatarios extra por el campo `to`.
  EMAIL_FORMAT = /\A[^@\s,;:<>"\\]+@[^@\s,;:<>"\\]+\.[^@\s,;:<>"\\]+\z/

  # Correo libre: asunto y cuerpo escritos a mano, sin plantilla. Lo usan los
  # flujos de Automations para mandar el informe final a una dirección propia.
  def send_message
    config = Current.account.jabvox_smtp_config
    return render json: { error: 'SMTP not configured' }, status: :unprocessable_entity if config&.address.blank?

    to = params[:to].to_s.strip
    subject = params[:subject].to_s.strip
    body = params[:body].to_s

    error = validate_message(to, subject, body)
    return render json: { error: error }, status: :unprocessable_entity if error

    deliver_message(config, to, subject, body)
    render json: { success: true, to: to }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def deliver_message(config, to, subject, body)
    Jabvox::EmailSenderService.new(
      account: Current.account,
      config: config,
      to: to,
      subject: subject,
      html_body: html_body_for(body),
      source: 'manual',
      user: current_user
    ).deliver!
  end

  def validate_message(to, subject, body)
    return 'Recipient email is required' if to.blank?
    return 'Recipient email is not valid' unless to.match?(EMAIL_FORMAT)
    return 'Subject is required' if subject.blank?
    return 'Body is required' if body.blank?

    nil
  end

  # El cuerpo se manda como HTML (única vía del servicio de envío), así que un
  # texto plano se escapa y sus saltos de línea se vuelven <br> para no perderse.
  def html_body_for(body)
    return body if ActiveModel::Type::Boolean.new.cast(params[:is_html])

    ERB::Util.html_escape(body).to_s.gsub("\n", "<br>\n")
  end

  # Mismo gateo que las plantillas de correo: sin rol personalizado se conserva
  # el comportamiento histórico; un rol personalizado necesita el permiso.
  def ensure_module_permission
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize_write!('jabvox_email_manage')
  end
end
