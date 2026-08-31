# frozen_string_literal: true

# SNAPSHOT del contexto de un run suspendido. Quien reanude será OTRO proceso
# (otro worker, incluso otro contenedor) y no comparte memoria con el que
# suspendió, así que vars/outputs/trigger viajan por la base de datos.
#
# Las GLOBALES no se guardan a propósito: se recargan frescas al reanudar, así
# un run suspendido días ve el valor vigente y nunca queda un secreto descifrado
# escrito en la BD.
module Jabvox::Flows::Engine::WaitState
  module_function

  # Snapshot redactado, listo para la columna jsonb.
  def capture(ctx)
    redact = ->(value) { Jabvox::Flows::Engine::Secrets.redact(value, ctx.secret_values) }
    { 'vars' => redact.call(ctx.vars), 'outputs' => redact.call(ctx.outputs),
      'trigger' => redact.call(ctx.trigger) }
  end

  # Devuelve las tres piezas del snapshot, tolerando un estado ausente o antiguo.
  def restore(raw)
    state = raw.is_a?(Hash) ? raw.stringify_keys : {}
    { vars: hash_of(state['vars']), outputs: hash_of(state['outputs']), trigger: hash_of(state['trigger']) }
  end

  def hash_of(value)
    value.is_a?(Hash) ? value.dup : {}
  end
end
