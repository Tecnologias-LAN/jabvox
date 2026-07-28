# Resuelve qué usuario de la cuenta presta su access token a Automations y valida
# que siga sirviendo. Sustituye al eliminado Automations::ServiceUserService.
#
# Los tokens de Jabvox son uno por usuario y no caducan: si esa persona sale, se
# degrada a agente o le rotan el token, las automatizaciones de la cuenta se paran.
class Automations::UserTokenService
  VALIDATION_ERRORS = {
    not_selected: 'No hay ningún usuario seleccionado para las automatizaciones de esta cuenta.',
    user_missing: 'El usuario seleccionado para las automatizaciones ya no existe en Jabvox.',
    not_member: 'El usuario seleccionado ya no pertenece a esta cuenta. ' \
                'Las automatizaciones están detenidas: elige otro usuario y reaprovisiona.',
    not_administrator: 'El usuario seleccionado ya no es administrador de esta cuenta ' \
                       '(ahora es agente). Un agente solo ve las bandejas de las que es miembro, ' \
                       'así que los flujos fallarían de forma errática. Elige un administrador.',
    not_confirmed: 'El usuario seleccionado no ha confirmado su cuenta. ' \
                   'La API de Jabvox rechaza los access tokens de usuarios sin confirmar (401).'
  }.freeze

  Validation = Struct.new(:valid, :reason, :user, keyword_init: true) do
    def valid?
      valid
    end

    def message
      reason && VALIDATION_ERRORS[reason]
    end
  end

  def initialize(account)
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
  end

  # `Account#administrators`/`#agents` ya resuelven el enum entero de AccountUser#role;
  # escribir aquí `role: 'administrator'` sería el error clásico con ese enum.
  def selectable_users
    { administrators: @account.administrators.order(:name), agents: @account.agents.order(:name) }
  end

  def selected_user
    config = @account.account_automation_config
    return nil if config.nil? || config.automations_user_id.blank?

    # `find_by` y no `find`: un id que ya no resuelve debe dar nil, no RecordNotFound.
    User.find_by(id: config.automations_user_id)
  end

  # Se llama ANTES DE CADA APROVISIONAMIENTO: el modo de fallo esperado es que la
  # selección envejezca mal, y hay que convertirlo en error explicable, no en un 401.
  def validate!
    user = selected_user
    return invalid(:not_selected) if @account.account_automation_config&.automations_user_id.blank?
    return invalid(:user_missing) if user.nil?

    membership = @account.account_users.find_by(user_id: user.id)
    return invalid(:not_member, user) if membership.nil?
    return invalid(:not_administrator, user) unless membership.administrator?
    return invalid(:not_confirmed, user) if user.confirmed_at.blank?

    Validation.new(valid: true, reason: nil, user: user)
  end

  # Crea el token SOLO si falta; nunca reemplaza el token personal del usuario.
  #
  # El `reload` es imprescindible: AccessTokenable#create_access_token sobrescribe el
  # método del `has_one` con un create suelto que no refresca la asociación en memoria.
  def ensure_token!
    validation = validate!
    return nil unless validation.valid?

    user = validation.user
    existing = user.access_token
    return existing.token if existing.present?

    created = user.create_access_token
    user.reload
    created.token
  end

  def status
    validation = validate!
    user = validation.user
    return { selected: false, valid: false, reason: validation.reason } if user.nil?

    token = user.access_token
    {
      selected: true,
      valid: validation.valid?,
      reason: validation.reason,
      message: validation.message,
      user_id: user.id,
      name: user.name,
      email: user.email,
      role: @account.account_users.find_by(user_id: user.id)&.role,
      confirmed: user.confirmed_at.present?,
      has_token: token.present?,
      token_created_at: token&.created_at,
      masked_token: mask(token&.token)
    }
  end

  private

  def invalid(reason, user = nil)
    Validation.new(valid: false, reason: reason, user: user)
  end

  # El token nunca se renderiza completo: 4 de 24 caracteres bastan para cotejarlo.
  def mask(raw)
    return nil if raw.blank?

    "•••• #{raw.to_s.last(4)}"
  end
end
