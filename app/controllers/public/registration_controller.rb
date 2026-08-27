# frozen_string_literal: true

# Registro público (sin autenticación): crea la cuenta y el usuario administrador PRIMERO,
# envía las credenciales por correo, y DESPUÉS solicita el pago. Así el usuario ya tiene
# acceso para revisar la plataforma antes de comprometerse al pago.
#
# Cuentas sin pago aprobado quedan en estado payment_pending y se eliminan automáticamente
# tras el periodo de gracia configurado en super_admin (JABVOX_PENDING_ACCOUNT_CLEANUP_DAYS).
#
# POST /public/register
#   {
#     "email": "usuario@empresa.com",
#     "name": "Juan Pérez",           # nombre del usuario
#     "account_name": "Empresa X",    # nombre de la cuenta (opcional)
#     "password": "SecurePass123!",
#     "password_confirmation": "SecurePass123!"
#   }
#
# Respuesta exitosa (201):
#   {
#     "account_id": 123,
#     "user_id": 456,
#     "email": "usuario@empresa.com",
#     "account_name": "Empresa X",
#     "message": "Cuenta creada exitosamente. Revisa tu correo para activar tu cuenta."
#   }
class Public::RegistrationController < ActionController::API
  # Excepción para errores de validación/negocio
  class RegistrationError < StandardError; end

  def create
    result = register_account
    render json: success_response(result), status: :created
  rescue RegistrationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    # Red de seguridad: cualquier validación del modelo que no hayamos replicado arriba
    # (p.ej. reglas de contraseña) devuelve 422 con el mensaje real, nunca un 500.
    render json: { error: e.record.errors.full_messages.to_sentence.presence || e.message },
           status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PublicRegistration] Error inesperado: #{e.message}\n#{e.backtrace.join("\n")}")
    render json: { error: 'Error al crear la cuenta. Inténtalo de nuevo.' }, status: :internal_server_error
  end

  private

  def register_account
    validate_params!

    ActiveRecord::Base.transaction do
      account = create_account
      user = create_user(account)
      link_user_as_admin(account, user)
      send_welcome_email(user, account)

      { account: account, user: user }
    end
  end

  def validate_params!
    raise RegistrationError, 'El correo es obligatorio' if params[:email].blank?
    raise RegistrationError, 'El nombre es obligatorio' if params[:name].blank?
    raise RegistrationError, 'La contraseña es obligatoria' if params[:password].blank?
    raise RegistrationError, 'Las contraseñas no coinciden' if params[:password] != params[:password_confirmation]

    email = params[:email].to_s.strip.downcase
    raise RegistrationError, 'Formato de correo inválido' unless email.match?(URI::MailTo::EMAIL_REGEXP)
    raise RegistrationError, 'El correo ya está registrado' if User.exists?(email: email)

    # Validar fortaleza de contraseña. Debe coincidir con la política del modelo User
    # (Devise :password_has_required_content): 1 minúscula, 1 mayúscula, 1 dígito y
    # 1 carácter especial. Si no la replicamos aquí, el save! del modelo lanza un 500
    # en vez de devolver un 422 amigable.
    password = params[:password].to_s
    raise RegistrationError, 'La contraseña debe tener al menos 8 caracteres' if password.length < 8
    # El gem devise-secure_password RECHAZA cualquier carácter fuera del set permitido
    # (letras ASCII, dígitos y el set especial). Los acentos/ñ (típicos en español) NO
    # están permitidos: hay que rechazarlos aquí con un 422 claro, o el save! del modelo
    # explota con un 500.
    if disallowed_chars?(password)
      raise RegistrationError, 'La contraseña solo admite letras (sin acentos ni ñ), números y estos símbolos: ! @ # $ % ^ & * ( ) _ + - = [ ] { } | " / \\ . , ` < > : ; ? ~ \''
    end
    raise RegistrationError, 'La contraseña debe incluir mayúscula, minúscula, número y un carácter especial' unless strong_password?(password)
  end

  # Set exacto de caracteres especiales permitidos por devise-secure_password.
  SPECIAL_CHARS = %r{[!@#$%^&*()_+\-=\[\]{}|"/\\.,`<>:;?~']}
  # Todo lo que el gem considera válido: letras ASCII, dígitos y el set especial. Cualquier
  # otra cosa (acentos, ñ, emojis, unicode) es rechazada por el modelo.
  ALLOWED_PASSWORD_CHARS = %r{\A[A-Za-z0-9!@#$%^&*()_+\-=\[\]{}|"/\\.,`<>:;?~' ]+\z}

  def strong_password?(password)
    password.match?(/[a-z]/) && password.match?(/[A-Z]/) &&
      password.match?(/[0-9]/) && password.match?(SPECIAL_CHARS)
  end

  def disallowed_chars?(password)
    !password.match?(ALLOWED_PASSWORD_CHARS)
  end

  def create_account
    account_name = params[:account_name].presence || derive_account_name
    Account.create!(
      name: account_name,
      locale: params[:locale].presence || 'es',
      status: :payment_pending
    )
  end

  def create_user(account)
    email = params[:email].to_s.strip.downcase
    user = User.new(
      name: params[:name].to_s.strip,
      email: email,
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )
    user.skip_confirmation! # Confirmación manual por correo si se desea
    user.save!
    user
  end

  def link_user_as_admin(account, user)
    account.account_users.create!(user: user, role: :administrator)
  end

  def send_welcome_email(user, account)
    cleanup_days = JabvoxBillingConfig.instance.unpaid_account_cleanup_days
    login_url = "#{ENV.fetch('FRONTEND_URL', 'https://app.jabvox.com')}/app/login"

    Jabvox::Billing::WelcomeMailer.welcome_email(
      email: user.email,
      name: user.name,
      account_name: account.name,
      login_url: login_url,
      cleanup_days: cleanup_days
    ).deliver_later

    Rails.logger.info("[PublicRegistration] Cuenta #{account.id} creada para #{user.email}, correo enviado")
  end

  def derive_account_name
    email = params[:email].to_s.strip.downcase
    email.split('@').first.to_s.tr('._-', ' ').strip.presence || 'Mi Cuenta Jabvox'
  end

  def success_response(result)
    {
      account_id: result[:account].id,
      user_id: result[:user].id,
      email: result[:user].email,
      account_name: result[:account].name,
      message: 'Cuenta creada exitosamente. Ahora puedes proceder al pago para activar tu plan.'
    }
  end
end
