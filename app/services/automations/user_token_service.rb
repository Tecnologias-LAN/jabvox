# Resuelve QUÉ usuario de una cuenta presta su access token a la plataforma
# Automations, y VALIDA que ese usuario siga sirviendo antes de cada
# aprovisionamiento.
#
# ─────────────────────────────────────────────────────────────────────────────
# QUÉ SUSTITUYE Y POR QUÉ
# ─────────────────────────────────────────────────────────────────────────────
# Antes existía Automations::ServiceUserService, que al activar el módulo CREABA
# un usuario `automations-service+<id>.<hash>@jabvox.invalid` con contraseña
# aleatoria y le emitía un token propio. Se ha eliminado: creaba de forma
# automática y silenciosa una cuenta de administrador permanente en el sistema,
# con un token que no caduca, cuyo ciclo de vida solo se podía gestionar desde
# esta pantalla. Si el código de esa pantalla desaparecía, la credencial
# sobrevivía sin panel de control.
#
# Ahora el super admin ELIGE explícitamente un usuario existente de la cuenta.
# La contrapartida —y hay que decirla, no esconderla— es que la credencial pasa a
# estar ATADA A UNA PERSONA:
#
#   - Los tokens de Jabvox son UNO POR USUARIO y NO CADUCAN
#     (AccessTokenable: `has_one :access_token`, sin expiración).
#   - Si esa persona sale de la empresa, se degrada a agente o le rotan el token,
#     las automatizaciones de la cuenta SE DETIENEN.
#   - Todo lo que hagan las automatizaciones queda registrado a nombre de esa
#     persona (Message#sender, auditoría), no de un robot.
#
# Por eso `validate!` se ejecuta ANTES DE CADA APROVISIONAMIENTO en vez de
# confiar en el esquema: el modo de fallo esperado es que la selección envejezca
# mal, y hay que convertirlo en un estado de error explicable en lugar de un 401
# opaco desde Automations.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ NO SE REGENERA NUNCA EL TOKEN
# ─────────────────────────────────────────────────────────────────────────────
# El botón "Regenerar token" del flujo anterior se ha eliminado y aquí NO hay
# `regenerate_token!`. Con un usuario de servicio dedicado, regenerar era
# inocuo. Con una persona real, `AccessToken` es uno por usuario: destruirlo y
# crear otro le revocaría a esa persona su token PERSONAL, rompiéndole la app
# móvil y cualquier integración propia que tuviera montada. No es una operación
# que el panel de Automations pueda arrogarse.
#
# La vía de recuperación es `ensure_token!` (crear el token SOLO si falta, nunca
# reemplazarlo) combinada con el reaprovisionamiento, que reenvía el token
# EXISTENTE. Si el token de la persona está realmente comprometido, se rota desde
# el perfil de esa persona y luego se reaprovisiona.
class Automations::UserTokenService
  # Motivos por los que un usuario seleccionado deja de servir. Se devuelven como
  # símbolo (no como texto) para que el llamador decida el mensaje y para que un
  # cambio de redacción no rompa ninguna comparación.
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

  # Candidatos para el selector, agrupados por rol.
  #
  # Se devuelven los DOS grupos —administradores primero, agentes después— para
  # que la UI pueda filtrar por defecto a administradores (que es lo correcto)
  # sin ocultar que existen agentes. Reutiliza `Account#administrators` y
  # `Account#agents`, que ya resuelven el enum entero de `AccountUser#role`
  # (`{ agent: 0, administrator: 1 }`); escribir aquí `role: 'administrator'`
  # sería el error clásico con este enum.
  def selectable_users
    { administrators: @account.administrators.order(:name), agents: @account.agents.order(:name) }
  end

  # El usuario elegido, o nil. No valida nada: solo resuelve la referencia.
  def selected_user
    config = @account.account_automation_config
    return nil if config.nil? || config.automations_user_id.blank?

    # `automations_user` es la asociación; se usa `find_by` sobre ella para que un
    # id que ya no resuelve (User borrado con la FK en :nullify aún sin propagar,
    # o dump parcial) devuelva nil en vez de lanzar RecordNotFound.
    User.find_by(id: config.automations_user_id)
  end

  # ¿Sigue sirviendo el usuario seleccionado? SE LLAMA ANTES DE CADA
  # APROVISIONAMIENTO (requisito §5.2).
  #
  # Comprueba las cuatro cosas que pueden haber cambiado desde que se eligió,
  # en orden de coste creciente y de forma que cada motivo sea distinguible:
  # existe → pertenece a la cuenta → sigue siendo administrador → está confirmado.
  #
  # No se valida "tiene token": `ensure_token!` lo crea si falta, así que su
  # ausencia no es un fallo del usuario sino un paso pendiente.
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

  # Access token del usuario seleccionado, creándolo SOLO si no lo tuviera.
  #
  # El `||` no es paranoia: AccessTokenable emite el token en un `after_create`,
  # pero los usuarios creados antes de que ese callback existiera pueden no
  # tenerlo, y devolver nil aquí es exactamente lo que produce el 401 opaco.
  #
  # EL `reload` ES IMPRESCINDIBLE, NO COSMÉTICO:
  # `AccessTokenable#create_access_token` (app/models/concerns/access_tokenable.rb:8-10)
  # SOBRESCRIBE el método que genera `has_one :access_token` con un
  # `AccessToken.create!(owner: self)` suelto, y ese create NO refresca la
  # asociación en memoria. Sin recargar, `user.access_token` seguiría devolviendo
  # nil (el valor cacheado de la comprobación anterior) y se enviaría un token
  # vacío a Automations. Por eso se lee el token del retorno de `create_access_token`
  # y además se recarga: así el objeto que ve el llamador queda consistente.
  #
  # NUNCA destruye ni reemplaza un token existente: es el token PERSONAL de esa
  # persona (ver la cabecera de la clase).
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

  # Resumen para la vista del super admin. NUNCA incluye el token en claro:
  # solo si existe, desde cuándo y un enmascarado de 4 caracteres.
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

  # El token NUNCA se renderiza completo (requisito §5.2). Se muestran los 4
  # últimos caracteres, lo justo para que el operador pueda cotejar de un vistazo
  # que Jabvox y Automations hablan del mismo token, sin que el HTML contenga una
  # credencial utilizable: un access token de Jabvox son 24 caracteres
  # (Devise.friendly_token), así que revelar 4 deja el resto inadivinable.
  def mask(raw)
    return nil if raw.blank?

    "•••• #{raw.to_s.last(4)}"
  end
end
