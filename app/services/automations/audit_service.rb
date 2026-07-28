# Registra QUÉ super-admin cambió el usuario de automatizaciones DE QUÉ cuenta,
# CUÁNDO y DESDE QUÉ IP (requisito §5.2).
#
# ═════════════════════════════════════════════════════════════════════════════
# EL PROBLEMA DE LA AUDITORÍA EN EL SUPER ADMIN, Y CÓMO SE RESUELVE
# ═════════════════════════════════════════════════════════════════════════════
# El inventario previo advertía: `SuperAdmin::ApplicationController` no define
# `current_user` ni puebla `Audited.store[:current_user]`, así que marcar el
# modelo como `audited` dejaría `audits.user_id` en NULL. Eso es CIERTO, y hay un
# detalle adicional que lo hace peor: `Enterprise::AuditLog#log_additional_information`
# hace `update_columns(username: user&.email)`, así que con el store vacío
# quedarían en NULL las DOS columnas que identifican al actor (`user_id` y
# `username`) — un registro de auditoría que dice qué cambió pero no quién.
#
# Dos hallazgos permiten arreglarlo sin tocar el controlador base (que es
# compartido por todo el super admin y no debe modificarse para un módulo):
#
#   1. `current_super_admin` SÍ EXISTE. Lo genera Devise a partir del modelo
#      SuperAdmin (`before_action :authenticate_super_admin!`), y ya hay
#      precedente de uso para trazar acciones de super admin en
#      SuperAdmin::PushDiagnosticsController#log_super_admin_action (línea 55).
#      El inventario buscaba `current_user`, que efectivamente no existe; el
#      helper se llama de otra forma.
#
#   2. `SuperAdmin < User` (app/models/super_admin.rb:48) — es STI sobre la tabla
#      `users`. Por eso encaja en `audits.user_id`/`user_type` sin violentar nada:
#      es un User de verdad, con su propio id en la misma tabla a la que apuntan
#      el resto de auditorías.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ SE ESCRIBE LA AUDITORÍA A MANO Y NO CON `audited` EN EL MODELO
# ─────────────────────────────────────────────────────────────────────────────
# Se podría haber puesto `audited` en AccountAutomationConfig y poblar
# `Audited.store[:current_user]` desde un `around_action`. Se ha descartado:
#
#   a) `audited` audita CUALQUIER cambio del modelo, y este modelo se escribe en
#      cada `test_connection` y en cada recálculo de estado (last_status,
#      last_error, automations_state). La señal que importa —"alguien cambió el
#      usuario de las automatizaciones"— quedaría sepultada bajo decenas de filas
#      de diagnóstico automático.
#   b) `audited` volcaría `audited_changes` con TODAS las columnas cambiadas,
#      incluida `api_key_jabvox`. Está cifrada en reposo, pero la auditoría
#      guardaría su valor en un jsonb que NO lo está: se filtraría la credencial
#      a una tabla sin cifrar. Habría que acordarse de excepcionarla
#      (`except: [:api_key_jabvox]`), y ese "acordarse" es una bomba de relojería
#      para la próxima columna sensible que alguien añada.
#   c) Un `around_action` que puebla `Audited.store` en el controlador base
#      cambiaría el comportamiento de auditoría de TODO el super admin de golpe
#      —empezarían a registrarse con actor cambios de todos los modelos audited—,
#      que es un efecto mucho mayor que el pedido y afecta a pantallas que otro
#      agente está tocando ahora mismo.
#
# Escribir UNA fila explícita por cambio de usuario da exactamente el rastro
# pedido, con el actor poblado, sin ruido y sin riesgo de filtrar secretos.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ DUPLICAR EL RASTRO (fila de config + tabla audits)
# ─────────────────────────────────────────────────────────────────────────────
# Además de esta fila, el controlador escribe
# `automations_user_set_at/_by_id/_ip` en la propia fila de configuración. No es
# redundancia gratuita: la tabla `audits` es enterprise y podría purgarse o
# rotarse, mientras que el rastro en la fila de configuración es el que se pinta
# en la pantalla y sobrevive a cualquier política de retención. Uno es el
# histórico completo; el otro, el estado actual verificable de un vistazo.
class Automations::AuditService
  AUDITABLE_ACTION = 'automations_user_changed'.freeze

  # `actor` es el `current_super_admin` del controlador (puede ser nil en consola).
  # `request` se usa solo para la IP; se pasa el objeto en vez de la IP suelta para
  # que el llamador no tenga que acordarse de qué atributo es el correcto.
  def initialize(account:, actor:, request: nil)
    @account = account
    @actor = actor
    @request = request
  end

  def remote_ip
    @request&.remote_ip
  end

  def actor_id
    @actor&.id
  end

  # Registra el cambio de usuario de automatizaciones.
  #
  # `previous_user` / `new_user` son User o nil (nil = "no había" / "se quitó").
  # Se guardan id, email Y nombre de ambos: el email es el dato que un auditor
  # reconoce, pero si esa persona se borra del sistema el id dejaría de resolver,
  # así que el email queda CONGELADO en el registro. Es el mismo criterio que
  # `Enterprise::AuditLog` aplica con `username`.
  #
  # NO SE REGISTRA NINGÚN TOKEN, ni completo ni enmascarado: el objeto de la
  # auditoría es quién tomó la decisión, no la credencial que se movió.
  def log_user_change(previous_user:, new_user:)
    write_audit(
      previous_user_id: previous_user&.id,
      previous_user_email: previous_user&.email,
      new_user_id: new_user&.id,
      new_user_email: new_user&.email,
      new_user_name: new_user&.name
    )
    log_to_rails_log(previous_user, new_user)
  end

  private

  # Fila en `audits` vía el mismo `Audited.audit_class` que usa el resto del
  # sistema (Enterprise::AuditLog, ver config/initializers/audited.rb), para que
  # el cambio aparezca en el visor de auditoría de la cuenta junto a los demás.
  #
  # `auditable` = la CUENTA, no la fila de configuración: quien audita busca "qué
  # le pasó a la cuenta 2", y `Enterprise::AuditLog#log_additional_information`
  # rellena `associated_*` automáticamente cuando el auditable es un Account, con
  # lo que el registro queda enganchado al visor por cuenta sin trabajo extra.
  #
  # `user_type: 'User'` y no 'SuperAdmin': STI guarda la clase BASE en las
  # asociaciones polimórficas, y las demás auditorías del sistema usan 'User'.
  # Poner 'SuperAdmin' rompería el `belongs_to :user, polymorphic: true` de la
  # gema al resolver el actor.
  #
  # Todo el bloque va en un rescue: la auditoría NO debe poder tumbar la operación
  # que audita. Si la tabla `audits` no existe (instalación community sin el
  # esquema enterprise) o el registro falla, se pierde la fila de `audits` pero
  # queda el log y —lo importante— las columnas `automations_user_set_*` de la
  # configuración, que las escribe el controlador fuera de aquí.
  def write_audit(changes)
    return unless audits_available?

    Audited.audit_class.create!(
      auditable: @account,
      action: AUDITABLE_ACTION,
      audited_changes: changes.stringify_keys,
      user_id: actor_id,
      user_type: actor_id ? 'User' : nil,
      username: @actor&.email,
      remote_address: remote_ip,
      request_uuid: @request&.request_id
    )
  rescue StandardError => e
    Rails.logger.warn("[Automations] no se pudo registrar la auditoría del cambio de usuario: #{e.message}")
  end

  # La tabla `audits` viene del esquema enterprise. Se comprueba en vez de
  # asumirla para que una instalación sin ella no reciba un 500 al guardar el
  # usuario. `table_exists?` va a la caché del esquema, no a la BD, en cada llamada.
  def audits_available?
    Audited.audit_class.table_exists?
  rescue StandardError
    false
  end

  # Segundo canal, a propósito: el log de la aplicación se agrega y se retiene
  # fuera de la base de datos, así que sobrevive a un `DELETE FROM audits` y a la
  # restauración de un dump antiguo. Mismo formato `[SuperAdmin]` que
  # SuperAdmin::PushDiagnosticsController para que los dos sean grepeables juntos.
  def log_to_rails_log(previous_user, new_user)
    Rails.logger.info(
      "[SuperAdmin] automations user changed for account #{@account.id}: " \
      "#{previous_user&.id || 'ninguno'} -> #{new_user&.id || 'ninguno'} " \
      "(actor_id=#{actor_id}, actor_email=#{@actor&.email}, ip=#{remote_ip})"
    )
  end
end
