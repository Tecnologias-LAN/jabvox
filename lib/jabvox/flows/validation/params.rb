# frozen_string_literal: true

# Reglas sobre los PARAMS de un nodo que necesita la validación: qué cuenta como
# vacío, qué defaults aplica el catálogo y cuándo un campo es visible.
module Jabvox::Flows::Validation::Params
  module_function

  # Params del nodo FUSIONADOS con los `default` del catálogo. El editor no
  # persiste lo que el usuario nunca tocó, pero el motor sí aplica los defaults:
  # validar sin ellos daría falsos "obligatorio vacío".
  def effective(specs, raw)
    defaults = specs.each_with_object({}) do |spec, acc|
      spec = spec.stringify_keys
      acc[spec['key'].to_s] = spec['default'] if spec.key?('default')
    end
    defaults.merge(raw.is_a?(Hash) ? raw.stringify_keys : {})
  end

  # `false` y `0` son valores legítimos y NO son vacíos; sí lo son nil, el texto
  # en blanco, el array sin elementos y el objeto sin claves.
  def empty_value?(value)
    case value
    when nil then true
    when String then value.strip == ''
    when Array, Hash then value.empty?
    else false
    end
  end

  # Un param oculto por su visibilidad condicional NO puede ser obligatorio: el
  # usuario no tiene ninguna casilla donde rellenarlo. Si se declaran las dos
  # formas se exigen ambas (AND), igual que el formulario del editor.
  def visible?(spec, params)
    spec = spec.stringify_keys
    one = spec['visibleWhen']
    all = spec['visibleWhenAll']
    return false if one.present? && !condition_met?(one, params)

    Array(all).all? { |cond| condition_met?(cond, params) }
  end

  def condition_met?(condition, params)
    cond = condition.stringify_keys
    Array(cond['values']).include?(params[cond['param'].to_s])
  end

  def required?(spec)
    spec.stringify_keys['required'] == true
  end

  def key_of(spec)
    spec.stringify_keys['key'].to_s
  end

  def label_of(spec)
    spec = spec.stringify_keys
    spec['label'].presence || spec['key'].to_s
  end
end
