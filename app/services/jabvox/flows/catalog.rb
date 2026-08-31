# frozen_string_literal: true

# CATÁLOGO DE NODOS para la interfaz: tipo, etiqueta, puertos y la especificación
# de params con la que el editor dibuja el panel de configuración.
#
# El JSON es la MISMA definición que ya usaba el editor original, así que el
# panel se renderiza sin reescribir nada. La paridad con los tipos que el motor
# sabe ejecutar se comprueba en spec: un tipo del catálogo que el registro no
# conozca sería un nodo que se puede arrastrar pero no ejecutar.
class Jabvox::Flows::Catalog
  PATH = Rails.root.join('lib/jabvox/flows/catalog/nodes.json')

  class << self
    # Definiciones completas, ya congeladas.
    def all
      @all ||= JSON.parse(PATH.read).map(&:freeze).freeze
    end

    def types
      @types ||= all.pluck('type').freeze
    end

    def find(type)
      by_type[type]
    end

    def by_type
      @by_type ||= all.index_by { |node| node['type'] }.freeze
    end

    # Especificación de params de un tipo, que es lo que consume la validación
    # de obligatorios y el panel de configuración.
    def params_spec(type)
      Array(find(type)&.dig('params'))
    end

    def reset!
      @all = @types = @by_type = nil
    end
  end
end
