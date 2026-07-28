# Máquina de estados de la integración Automations POR CUENTA (§7).
#
# ─────────────────────────────────────────────────────────────────────────────
# LOS ESTADOS Y SU ORDEN
# ─────────────────────────────────────────────────────────────────────────────
#   sin_config_global : falta alguna de las condiciones de la config GLOBAL.
#   pendiente_token   : global OK + módulo activo, pero SIN usuario seleccionado
#                       (o el seleccionado ya no sirve).
#   ok                : aprovisionado y verificado.
#   error_auth        : Automations devolvió 401/403.
#
# ─────────────────────────────────────────────────────────────────────────────
# LA REGLA QUE GOBIERNA TODO: NUNCA `ok` SI FALTA UNA CAPA PREVIA
# ─────────────────────────────────────────────────────────────────────────────
# `recalculate` NO es un setter: es un derivador. Se evalúan las capas de abajo
# arriba y se devuelve la PRIMERA que falla, sin importar lo que dijera el estado
# guardado. Así un `ok` histórico no puede sobrevivir a que se borre la Provision
# Key global ni a que el usuario elegido deje de ser administrador: al siguiente
# render la cuenta ya no dice `ok`.
#
# Es deliberado que el estado sea DERIVADO y no solo almacenado. Un estado
# únicamente almacenado se queda obsoleto en silencio, que es precisamente el
# modo de fallo que esta pantalla existe para hacer visible. Se persiste (columna
# `automations_state`) para poder consultarlo sin recalcular y para tener el
# histórico, pero la verdad se recalcula.
#
# ─────────────────────────────────────────────────────────────────────────────
# ACTIVAR EL MÓDULO NO APROVISIONA (§7)
# ─────────────────────────────────────────────────────────────────────────────
# El toggle solo mueve la cuenta a `pendiente_token`. El aprovisionamiento ocurre
# cuando hay usuario elegido. Antes, activar creaba un usuario y disparaba el
# aprovisionamiento en el mismo clic: el operador no tenía forma de revisar con
# qué identidad iba a conectarse la cuenta antes de que ocurriera.
class Automations::StateService
  # Enteros estables: son valores persistidos, así que reordenarlos reescribiría
  # el significado de las filas existentes. Se añaden al final, nunca en medio.
  STATES = {
    sin_config_global: 0,
    pendiente_token: 1,
    ok: 2,
    error_auth: 3
  }.freeze

  # Cómo se pinta cada estado y qué significa. Vive aquí, junto a la definición
  # del estado, para que añadir un estado no deje la vista pintando un hueco.
  PRESENTATION = {
    sin_config_global: {
      label: 'Sin configuración global',
      color: '#991b1b', background: '#fee2e2',
      detail: 'Falta configuración global de Automations (Service URL, Provision Key, ' \
              'URL del iframe o URL de callback). Hasta que esté completa, ninguna cuenta puede conectarse.'
    },
    pendiente_token: {
      label: 'Pendiente de usuario',
      color: '#854d0e', background: '#fef9c3',
      detail: 'El módulo está activo pero NO hay un usuario válido que preste su token. ' \
              'Las automatizaciones de esta cuenta NO funcionan todavía. ' \
              'Elige un usuario abajo y pulsa "Guardar y aprovisionar".'
    },
    ok: {
      label: 'Aprovisionado',
      color: '#166534', background: '#dcfce7',
      detail: 'Cuenta aprovisionada y credencial verificada contra Automations.'
    },
    error_auth: {
      label: 'Error de autenticación',
      color: '#991b1b', background: '#fee2e2',
      detail: 'Automations rechazó la credencial (401/403). Revisa la API key de la cuenta ' \
              'y que el token del usuario seleccionado siga siendo válido, y reaprovisiona.'
    }
  }.freeze

  def initialize(account)
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
  end

  # ¿Está completa la configuración GLOBAL? Delega en el servicio que ya conoce
  # las claves globales en vez de releer InstallationConfig por su cuenta: si
  # mañana se añade una condición global, este método no tiene que enterarse.
  #
  # NOTA: la comprobación autenticada de la config global (el "Probar conexión"
  # global) la está implementando otro agente en
  # SuperAdmin::AutomationsConfigsController. Aquí solo se mira la PRESENCIA de la
  # configuración, no su validez remota, para no acoplar el render de esta página
  # a una llamada de red.
  def global_configured?
    Automations::ProvisioningService.configured?
  end

  # Estado REAL de la cuenta, derivado de las capas. Ver la cabecera.
  #
  # `remote_result` (opcional): el Result de la última llamada remota que acabe de
  # hacer el llamador. Solo se usa para distinguir `error_auth` de un fallo de red
  # cualquiera: un timeout no es un problema de credenciales y no debe marcar la
  # cuenta como `error_auth`.
  def recalculate(remote_result: nil)
    return :sin_config_global unless global_configured?

    config = @account.account_automation_config
    return :pendiente_token if config.nil? || !config.enabled?

    # Sin usuario válido no se puede estar aprovisionado, dijera lo que dijera el
    # estado anterior. Cubre a la vez "nunca se eligió" y "el elegido envejeció mal".
    return :pendiente_token unless Automations::UserTokenService.new(@account).validate!.valid?

    return :error_auth if auth_failure?(remote_result)
    # Un fallo remoto que NO es de autenticación (red, 5xx) no cambia el estado del
    # ciclo de vida: la cuenta sigue aprovisionada, es el servicio el que no
    # responde. Eso se cuenta con last_error, no degradando el estado.
    return :error_auth if remote_result.nil? && config.automations_state == STATES[:error_auth]

    :ok
  end

  # Recalcula Y PERSISTE. Devuelve el símbolo del estado resultante.
  #
  # `update_column` y no `update!`: esto se llama desde el render de `index`, que
  # es una petición GET. Disparar validaciones y callbacks (y por tanto una
  # auditoría de `audited`) en cada visita a la página generaría ruido de
  # auditoría por el simple hecho de MIRAR la pantalla. Solo se escribe si el
  # valor cambia realmente.
  def recalculate!(remote_result: nil)
    state = recalculate(remote_result: remote_result)
    config = @account.account_automation_config
    return state if config.nil?

    desired = STATES.fetch(state)
    config.update_column(:automations_state, desired) if config.automations_state != desired # rubocop:disable Rails/SkipsModelValidations

    state
  end

  private

  # ¿El fallo remoto es de CREDENCIALES (401/403) y no de red?
  #
  # ProvisioningService devuelve el error ya formateado como texto
  # ("Automations respondió 401: ...", ver #remote_error_message), no el objeto
  # response, así que aquí solo se puede mirar el mensaje. Se acota a `\b40[13]\b`
  # para no confundir un 401 con, por ejemplo, un cuerpo que mencione 4013.
  def auth_failure?(remote_result)
    return false if remote_result.nil?
    return false if remote_result.success?

    remote_result.error.to_s.match?(/respondió\s+40[13]\b/)
  end
end
