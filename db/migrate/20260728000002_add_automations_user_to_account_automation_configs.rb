# frozen_string_literal: true

# Selector de USUARIO para las automatizaciones + máquina de estados por cuenta.
#
# ─────────────────────────────────────────────────────────────────────────────
# 1. automations_user_id — QUIÉN presta su token
# ─────────────────────────────────────────────────────────────────────────────
# Sustituye al usuario de servicio que se creaba solo (`automations-service+N…
# @jabvox.invalid`). Ahora el super admin ELIGE un usuario existente de la
# cuenta y es su access token el que se envía a Automations.
#
# POR QUÉ UNA FK A `users` Y NO A `account_users`:
#   - Lo que se envía a Automations es el access token, y `AccessToken` es
#     polimórfico sobre el OWNER (`users.id`), no sobre la membresía. Apuntar a
#     account_users obligaría a un salto extra en cada aprovisionamiento.
#   - La pertenencia a la cuenta se valida EN CADA aprovisionamiento
#     (Automations::UserTokenService#validate!), no se delega al esquema: un
#     usuario puede seguir existiendo y haber sido expulsado de la cuenta, y ese
#     caso tiene que producir un estado de error explicable, no un dato ausente.
#
# ON DELETE SET NULL (`on_delete: :nullify`): si el User se borra de verdad, la
# cuenta debe quedar SIN usuario seleccionado (estado `pendiente_token`), no con
# una FK huérfana ni con la fila de configuración arrastrada al borrado. Un
# `:cascade` aquí sería destructivo: perdería la config entera (límite de flujos,
# API key, remote_account_id) por haber borrado a una persona.
#
# NO se añade índice único: dos cuentas pueden apoyarse en el mismo usuario si
# esa persona es administradora de ambas. Sí se indexa para poder responder
# rápido a "¿qué cuentas se romperían si desactivo a este usuario?".
#
# ─────────────────────────────────────────────────────────────────────────────
# 2. automations_state — máquina de estados (§7)
# ─────────────────────────────────────────────────────────────────────────────
# DECISIÓN: columna NUEVA de tipo INTEGER, en vez de reciclar `last_status`.
#
# `last_status` es un string libre que hoy guarda 'ok'/'error' y que se escribe
# desde cuatro sitios distintos como DIAGNÓSTICO de la última llamada remota
# (incluido test_connection, que no aprovisiona nada). Son dos conceptos
# diferentes:
#
#   - last_status  = "cómo fue la última operación" (efímero, informativo).
#   - automations_state = "en qué punto del ciclo de vida está esta cuenta"
#     (persistente, y es lo que decide qué puede hacerse y qué avisos se pintan).
#
# Fundirlos obligaría a que un `test_connection` fallido degradara el estado del
# ciclo de vida, y un 'ok' de test_connection no puede significar "aprovisionado
# y verificado". Además `pendiente_token` no es el resultado de ninguna llamada:
# es la ausencia de una.
#
# ENTERO y no string, siguiendo el patrón de la casa (`AccountUser#role` =
# `{ agent: 0, administrator: 1 }`): con `enum` de Rails los valores válidos
# quedan cerrados en el modelo —un typo revienta al asignar, no seis meses
# después al comparar— y el índice es más compacto. Se conserva `last_status`
# intacto para no romper la UI ni el histórico existente.
#
# DEFAULT 0 (`sin_config_global`): es el estado correcto para una fila recién
# creada y, sobre todo, para el BACKFILL. Ninguna cuenta existente tiene todavía
# `automations_user_id`, así que ninguna puede estar legítimamente en `ok`: el
# recálculo (Automations::StateService) las llevará a `pendiente_token` o a
# `sin_config_global` según la config global en el primer render. Arrancar en 0
# cumple la regla "nunca `ok` si falta una capa previa" incluso antes de que
# nadie recalcule nada.
# ─────────────────────────────────────────────────────────────────────────────
# 3. Rastro de auditoría en la propia fila
# ─────────────────────────────────────────────────────────────────────────────
# `automations_user_set_at/_by_id/_ip`: quién eligió al usuario, cuándo y desde
# qué IP. Es el rastro MÍNIMO garantizado, independiente de la gema `audited`
# (ver Automations::AuditService y el comentario de POR QUÉ DUPLICAR ahí): vive
# en la fila de configuración, se lee sin cruzar tablas y no depende de que
# `Audited.store[:current_user]` esté poblado.
#
# `automations_user_set_by_id` es un bigint SIN foreign key A PROPÓSITO: apunta a
# un `SuperAdmin`, que es STI sobre `users`, pero un registro de auditoría no
# debe poder ser borrado en cascada ni bloquear el borrado del super admin. Si esa
# cuenta desaparece, el id debe permanecer como dato histórico aunque ya no
# resuelva — es exactamente el mismo criterio por el que `audits.user_id` tampoco
# tiene FK en el esquema de la gema.
#
# Se escriben up/down explícitos en vez de `change`: `remove_reference` necesita
# soltar la constraint ANTES de la columna, y el orden inverso de los
# `remove_column` deja constancia de cómo se deshace.
class AddAutomationsUserToAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  def up
    add_reference :account_automation_configs, :automations_user,
                  foreign_key: { to_table: :users, on_delete: :nullify },
                  index: true, null: true
    add_column :account_automation_configs, :automations_state, :integer, default: 0, null: false
    add_column :account_automation_configs, :automations_user_set_at, :datetime, null: true
    add_column :account_automation_configs, :automations_user_set_by_id, :bigint, null: true
    add_column :account_automation_configs, :automations_user_set_ip, :string, null: true
  end

  def down
    remove_column :account_automation_configs, :automations_user_set_ip
    remove_column :account_automation_configs, :automations_user_set_by_id
    remove_column :account_automation_configs, :automations_user_set_at
    remove_column :account_automation_configs, :automations_state
    remove_reference :account_automation_configs, :automations_user,
                     foreign_key: { to_table: :users }, index: true
  end
end
