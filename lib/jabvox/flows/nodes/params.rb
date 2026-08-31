# frozen_string_literal: true

# Lectura de params con RESPALDO que tolera la CADENA VACÍA. El formulario del
# panel manda '' cuando el campo se deja en blanco, y en Ruby '' es truthy: con
# `||` el respaldo nunca entraba y viajó un idioma vacío que Meta rechazó.
module Jabvox::Flows::Nodes::Params
  module_function

  # ¿El valor cuenta como "no puesto"? nil o solo espacios.
  def blank_param?(value)
    value.nil? || (value.is_a?(String) && value.strip == '')
  end

  # Primer candidato no vacío ya como texto recortado; '' si todos lo están.
  def first_filled(*candidates)
    found = candidates.find { |c| !blank_param?(c) }
    found.nil? ? '' : found.to_s.strip
  end

  # Número con respaldo: '' cae al defecto en vez de convertirse en 0.
  def number_or(value, fallback)
    return fallback if blank_param?(value)

    Float(value.to_s)
  rescue ArgumentError, TypeError
    fallback
  end

  # Entero con respaldo, acotado opcionalmente a un rango.
  def int_or(value, fallback, min: nil, max: nil)
    number = number_or(value, fallback)
    number = number.finite? ? number.truncate : fallback
    number = [number, min].max if min
    number = [number, max].min if max
    number
  end

  # Booleano OPT-IN: solo `true` (o 'true') activa. Los flujos guardados antes
  # de existir el param no traen la clave y quedan exactamente como estaban.
  def opt_in?(value)
    value == true || value.to_s.strip.downcase == 'true'
  end

  # Booleano OPT-OUT: solo `false` explícito desactiva.
  def opt_out?(value)
    !(value == false || value.to_s.strip.downcase == 'false')
  end

  # Lista de textos no vacíos desde un array o un texto separado por comas.
  def str_list(value)
    items = value.is_a?(Array) ? value : value.to_s.split(',')
    items.map { |v| v.to_s.strip }.compact_blank
  end

  # Id OBLIGATORIO. Un id vacío (plantilla que no resuelve) generaba rutas rotas
  # y errores ilegibles; se corta antes diciendo QUÉ campo falta.
  def require_id!(value, label)
    raw = value.to_s.strip
    return raw if raw.present?

    raise Jabvox::Flows::Engine::ExecutionError,
          "Falta #{label}: llegó vacío. Revisa ese campo del paso; si usas una plantilla, " \
          'comprueba que la ruta existe (dentro de "Repetir por elemento" se usa {{item.…}}).'
  end
end
