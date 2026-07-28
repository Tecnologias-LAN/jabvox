# Gestiona el USUARIO DE SERVICIO que la plataforma Automations usa para
# leer/escribir datos de UNA cuenta concreta de Jabvox.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ EXISTE
# ─────────────────────────────────────────────────────────────────────────────
# Antes se enviaba a Automations el access token del PRIMER administrador humano
# que se encontrara en la cuenta (`account_users.where(role: :administrator).first`).
# Eso tenía tres fallos:
#
#   1. TRAZABILIDAD: todo lo que hacían las automatizaciones quedaba registrado
#      en Jabvox como hecho por esa persona (mensajes con su sender, auditoría,
#      created_by...). Imposible distinguir un robot de un humano.
#   2. FRAGILIDAD: si esa persona se iba de la empresa, se le borraba de la
#      cuenta o se le rotaba el token, las automatizaciones se caían en silencio.
#   3. FALLOS AL ACTIVAR: ese administrador podía no tener AccessToken (usuarios
#      antiguos, creados antes del `after_create :create_access_token` de
#      AccessTokenable), y el aprovisionamiento fallaba o mandaba un token nulo,
#      produciendo el 401 que ve el operador al probar la integración.
#
# Con un usuario de servicio DEDICADO por cuenta: identidad propia (trazable),
# ciclo de vida controlado por nosotros (no se va con las personas) y token
# regenerable desde el super admin sin tocar a nadie.
#
# ─────────────────────────────────────────────────────────────────────────────
# EL EMAIL: POR QUÉ ESTE PATRÓN Y NO OTRO
# ─────────────────────────────────────────────────────────────────────────────
# Chatwoot valida la unicidad del email de forma GLOBAL (Devise :validatable
# sobre users.email; el scope por cuenta está comentado en User). Así que el
# patrón tiene que ser imposible de colisionar en dos sentidos:
#
#   a) Contra una PERSONA real: el dominio es `jabvox.invalid`. `.invalid` es un
#      TLD reservado por la RFC 2606 §2 que NUNCA se delega en el DNS raíz, así
#      que nadie puede registrar ese dominio ni recibir correo en él. Un humano
#      jamás va a tener ese email, y si alguien lo intentara, no podría probar su
#      propiedad (no hay buzón: el correo de confirmación no llega a ninguna
#      parte, lo que además es deseable — ver más abajo).
#
#   b) Contra OTRA INSTALACIÓN de Jabvox: se incrusta el INSTALLATION_IDENTIFIER
#      (UUID generado una vez por instalación, ver JabvoxHub.installation_identifier).
#      Sin él, restaurar un dump de la instancia A sobre la instancia B, o
#      fusionar bases de datos, colisionaría en `automations+2@...`, porque la
#      cuenta 2 existe en las dos. Con el UUID, el email de la cuenta 2 de A es
#      distinto del de la cuenta 2 de B. Se usan los 12 primeros hex del UUID
#      (48 bits): suficiente para que dos instalaciones cualesquiera no choquen,
#      y mantiene el email legible en los listados.
#
# Resultado: `automations-service+<account_id>.<inst12>@jabvox.invalid`
# El `+<...>` va en la local-part (subdirección estilo RFC 5233) para que a
# simple vista se lea "el usuario de automatizaciones de la cuenta N".
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ NO PUEDE INICIAR SESIÓN COMO UNA PERSONA
# ─────────────────────────────────────────────────────────────────────────────
#   - PASSWORD ALEATORIO Y NO RECUPERABLE: se genera con SecureRandom y NO se
#     guarda, ni se muestra, ni se devuelve. Solo queda su bcrypt en
#     encrypted_password. Nadie —ni el super admin— lo conoce.
#   - NO SE PUEDE RESETEAR: "¿Olvidaste tu contraseña?" envía el enlace al email,
#     y el email está en un dominio `.invalid` que no existe. El correo se
#     descarta en el MTA; no hay buzón que pueda recibir el token de reseteo.
#     Esta es la razón de fondo para elegir un TLD reservado en vez de un
#     subdominio real: convierte "sin buzón" en una garantía de la RFC, no en
#     una configuración que alguien pueda cambiar por descuido.
#   - SÍ ESTÁ CONFIRMADO (`skip_confirmation!`, el mismo mecanismo que usa
#     Chatwoot en db/seeds.rb, lib/seeders/account_seeder.rb y
#     enterprise/app/builders/saml_user_builder.rb): la API con access token
#     rechaza usuarios sin confirmar, así que sin esto las automatizaciones
#     darían 401. Confirmado ≠ con credenciales usables: el password sigue
#     siendo desconocido.
#
# ─────────────────────────────────────────────────────────────────────────────
# CÓMO SE DISTINGUE DE UNA PERSONA
# ─────────────────────────────────────────────────────────────────────────────
# No se añade columna a `users`: sería una migración sobre la tabla más caliente
# del sistema para un flag que solo interesa a este módulo. Se usa
# `custom_attributes` (jsonb ya existente en users):
#
#   { "jabvox_service_user" => "automations", "jabvox_service_account_id" => N }
#
# Es el marcador AUTORITATIVO (`service_user?`): el email es un heurístico que
# podría cambiar, el atributo es explícito. Además el nombre visible
# ("Automatizaciones (servicio)") lo delata en cualquier listado de agentes.
class Automations::ServiceUserService
  # Dominio reservado por RFC 2606: no se delega en el DNS, así que no puede
  # registrarse ni recibir correo. Ver la explicación de cabecera.
  SERVICE_EMAIL_DOMAIN = 'jabvox.invalid'.freeze
  # Prefijo de la local-part. Legible a propósito en los listados de agentes.
  SERVICE_EMAIL_PREFIX = 'automations-service'.freeze
  # Cuántos hex del INSTALLATION_IDENTIFIER se incrustan (48 bits).
  INSTALLATION_SUFFIX_LENGTH = 12
  # Nombre visible. En español y con "(servicio)" para que ningún operador lo
  # confunda con una persona al mirar la lista de agentes de la cuenta.
  SERVICE_USER_NAME = 'Automatizaciones (servicio)'.freeze
  # Claves en users.custom_attributes que marcan al usuario como de servicio.
  SERVICE_FLAG_KEY = 'jabvox_service_user'.freeze
  SERVICE_FLAG_VALUE = 'automations'.freeze
  SERVICE_ACCOUNT_KEY = 'jabvox_service_account_id'.freeze

  def initialize(account)
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
  end

  # ¿Este User es un usuario de servicio de Automations?
  # Se comprueba por custom_attributes, NO por el email: el atributo es el
  # marcador explícito y sobrevive a un cambio del patrón de email.
  def self.service_user?(user)
    return false if user.nil?

    user.custom_attributes.is_a?(Hash) && user.custom_attributes[SERVICE_FLAG_KEY] == SERVICE_FLAG_VALUE
  end

  # Email determinista de esta cuenta. Determinista = idempotencia: llamar dos
  # veces a ensure_user! encuentra al mismo usuario en vez de crear otro.
  def service_email
    "#{SERVICE_EMAIL_PREFIX}+#{@account.id}.#{installation_suffix}@#{SERVICE_EMAIL_DOMAIN}"
  end

  # El usuario de servicio de esta cuenta, o nil si aún no existe.
  # No crea nada: lo usa la vista del super admin para pintar el estado.
  # `from_email` en vez de `find_by(email:)` porque normaliza a minúsculas, igual
  # que el `before_validation` de User. El patrón ya se genera en minúsculas, pero
  # así la búsqueda no depende de eso.
  def find_user
    User.from_email(service_email)
  end

  # Crea (o reutiliza) el usuario de servicio y garantiza que sea administrador
  # de ESTA cuenta. IDEMPOTENTE: activar el módulo dos veces no duplica nada.
  #
  # Todo va en una transacción porque un usuario creado sin su AccountUser sería
  # un huérfano invisible: no aparecería en la cuenta, pero ocuparía el email y
  # bloquearía cualquier reintento posterior.
  #
  # ROL administrator: los nodos de Automations necesitan leer/escribir
  # conversaciones, contactos y etiquetas de toda la cuenta. Un `agent` solo ve
  # las bandejas de las que es miembro, así que un flujo fallaría de forma
  # errática según en qué bandeja cayera la conversación.
  def ensure_user!
    ActiveRecord::Base.transaction do
      user = find_or_create_service_user
      ensure_account_membership!(user)
      # Reactiva un usuario de servicio que se hubiera desactivado al deshabilitar
      # el módulo (ver deactivate_user!), para que reactivarlo lo devuelva a un
      # estado operativo sin intervención manual.
      reactivate!(user)
      user
    end
  end

  # Access token del usuario de servicio, creándolo si no lo tuviera.
  #
  # El `||=` no es paranoia: AccessTokenable crea el token en un
  # `after_create`, pero un usuario preexistente (o uno cuyo token se borrase a
  # mano) puede no tenerlo, y devolver nil aquí es exactamente lo que producía el
  # 401 opaco que había que diagnosticar.
  def ensure_token!
    user = ensure_user!
    (user.access_token || user.create_access_token).token
  end

  # Regenera el token: destruye el actual y crea uno nuevo. Es la vía de
  # recuperación cuando una cuenta se rompe (token filtrado, desincronizado con
  # Automations, o simplemente inválido).
  #
  # SE DESTRUYE, no se rota en su sitio, porque el token viejo debe dejar de
  # servir en el instante en que se regenera: si solo se sobrescribiera el valor
  # y algo fallara a mitad, quedarían dos credenciales vivas.
  #
  # Devuelve el token NUEVO para que el llamador lo reenvíe a Automations en la
  # misma operación; si no se reenviara, la cuenta quedaría con un token que
  # Jabvox acepta y Automations no conoce — peor que antes.
  # El `reload` es imprescindible, no cosmético: `AccessTokenable#create_access_token`
  # sobrescribe el método que genera `has_one`, hace un `AccessToken.create!` suelto
  # y NO refresca la asociación en memoria. Sin recargar, `user.access_token`
  # seguiría apuntando al registro que acabamos de destruir.
  def regenerate_token!
    user = ensure_user!
    ActiveRecord::Base.transaction do
      user.access_token&.destroy!
      user.reload.create_access_token.token
    end
  end

  # Desactiva el usuario de servicio al deshabilitar el módulo.
  #
  # POR QUÉ DESACTIVAR Y NO BORRAR: `Message#sender` es polimórfico y
  # `Conversation#assignee` apunta a `users.id`. Un flujo de Automations que haya
  # escrito mensajes los deja con `sender_id` = este usuario. Borrar el User
  # dispararía los `dependent: :nullify` / `:destroy_async` de User (mensajes sin
  # remitente, conversaciones sin asignar, notas huérfanas) y reescribiría
  # históricos que son justamente el rastro de auditoría que este usuario existe
  # para dejar. Destruir la prueba de lo que hizo el robot al apagar el robot es
  # lo contrario de la trazabilidad que se buscaba.
  #
  # Desactivar = revocar el ACCESO, conservar la IDENTIDAD:
  #   - Se destruye el access token: Automations deja de poder llamar a la API de
  #     esta cuenta de inmediato, incluso si conserva el token cifrado en su lado.
  #   - Se quita el AccountUser: el usuario deja de ser administrador y desaparece
  #     de la lista de agentes de la cuenta (no consume licencia ni ensucia los
  #     selectores de asignación).
  #   - El User permanece, con su marca `jabvox_service_user`, así que los
  #     mensajes y conversaciones históricos siguen resolviendo a "Automatizaciones
  #     (servicio)" en vez de a un hueco.
  #
  # Al reactivar, ensure_user! reconstruye el AccountUser y ensure_token! emite
  # un token nuevo sobre la MISMA identidad, así que el histórico y lo nuevo
  # quedan atribuidos al mismo actor.
  def deactivate_user!
    user = find_user
    return false if user.nil?

    ActiveRecord::Base.transaction do
      user.access_token&.destroy!
      @account.account_users.find_by(user_id: user.id)&.destroy!
      user.update!(custom_attributes: user.custom_attributes.to_h.merge('jabvox_service_deactivated_at' => Time.current))
    end
    true
  end

  # Resumen para la vista del super admin: con qué credencial se conecta esta
  # cuenta. Nunca incluye el token en claro, solo si existe y desde cuándo.
  def status
    user = find_user
    return { exists: false, email: service_email } if user.nil?

    token = user.access_token
    {
      exists: true,
      email: user.email,
      name: user.name,
      user_id: user.id,
      # Un usuario de servicio sin AccountUser está DESACTIVADO (ver deactivate_user!).
      member: @account.account_users.exists?(user_id: user.id),
      role: @account.account_users.find_by(user_id: user.id)&.role,
      has_token: token.present?,
      token_created_at: token&.created_at,
      confirmed: user.confirmed_at.present?
    }
  end

  private

  # Los N primeros hex del UUID de instalación, sin guiones. Ver cabecera.
  def installation_suffix
    JabvoxHub.installation_identifier.to_s.delete('-')[0, INSTALLATION_SUFFIX_LENGTH]
  end

  def find_or_create_service_user
    existing = find_user
    return existing if existing

    # Password aleatorio que cumple el validador `password_has_required_content`
    # (1 mayúscula + 1 minúscula + 1 número + 1 especial, ver
    # config/initializers/secure_password.rb). Mismo patrón que AgentBuilder,
    # pero aquí NADIE se lo queda: no se devuelve ni se registra.
    password = generate_unrecoverable_password
    user = User.new(
      email: service_email,
      name: SERVICE_USER_NAME,
      password: password,
      password_confirmation: password,
      custom_attributes: {
        SERVICE_FLAG_KEY => SERVICE_FLAG_VALUE,
        SERVICE_ACCOUNT_KEY => @account.id
      }
    )
    # Confirmación saltada: la API con access token exige usuario confirmado, y
    # el email es un `.invalid` al que nunca llegaría un correo de confirmación.
    user.skip_confirmation!
    user.save!
    user
  end

  # 32 caracteres aleatorios + los cuatro tipos exigidos por el validador.
  # Se genera, se usa para el bcrypt y se descarta con el objeto.
  def generate_unrecoverable_password
    "1!aA#{SecureRandom.alphanumeric(32)}"
  end

  # Garantiza que el usuario de servicio sea administrador de ESTA cuenta.
  # Si ya existe la membresía pero con rol `agent` (p.ej. alguien lo cambió a
  # mano), se corrige: con rol agent los flujos fallarían según la bandeja.
  def ensure_account_membership!(user)
    membership = @account.account_users.find_by(user_id: user.id)
    if membership.nil?
      # `availability: :offline` y `auto_offline: false`: no es una persona, no
      # debe contar como agente conectado ni entrar en el reparto automático de
      # conversaciones (round robin mira la disponibilidad).
      @account.account_users.create!(user_id: user.id, role: :administrator,
                                     availability: :offline, auto_offline: false)
    elsif !membership.administrator?
      membership.update!(role: :administrator)
    end
  end

  # Limpia la marca de desactivación al reactivar el módulo.
  def reactivate!(user)
    return unless user.custom_attributes.to_h.key?('jabvox_service_deactivated_at')

    user.update!(custom_attributes: user.custom_attributes.to_h.except('jabvox_service_deactivated_at'))
  end
end
