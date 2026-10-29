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

  # Mapa módulo (campo `module` del nodo) -> feature de cuenta que lo habilita.
  # Un módulo que NO esté aquí se considera SIEMPRE disponible (núcleo del CRM:
  # contactos, conversaciones, etiquetas, campañas), igual que los nodos sin
  # `module` (triggers/logic/integration, que son el motor y no se gatean).
  # Los nombres de feature son los canónicos de los concerns Jabvox::Account*Feature;
  # `account.feature_enabled?(name)` es el único punto de verdad.
  MODULE_FEATURE = {
    'calendario' => 'jabvox_calendar',
    'email' => 'jabvox_email',
    'estados' => 'jabvox_management_states',
    'kanban' => 'jabvox_kanban',
    'ordenes' => 'jabvox_products',
    'sms' => 'jabvox_sms',
    'tareas' => 'jabvox_tasks',
    'tipificaciones' => 'jabvox_forms',
    'whatsapp' => 'jabvox_whatsapp_templates'
  }.freeze

  class << self
    # Definiciones completas, ya congeladas.
    def all
      @all ||= JSON.parse(PATH.read).map(&:freeze).freeze
    end

    # Catálogo filtrado para una cuenta: oculta los nodos cuyo módulo NO está
    # activo en la cuenta. No muta las definiciones (devuelve un subconjunto del
    # array congelado). Núcleo y nodos sin módulo pasan siempre.
    def all_for(account)
      all.select { |node| module_available?(node['module'], account) }
    end

    # Nombres de módulo (gateados) activos / ocultos para la cuenta, para que el
    # editor pueda explicar por qué faltan nodos si hiciera falta.
    def modules_for(account)
      gated = MODULE_FEATURE.keys
      enabled, hidden = gated.partition { |mod| account.feature_enabled?(MODULE_FEATURE[mod]) }
      { enabled: enabled, hidden: hidden }
    end

    def module_available?(mod, account)
      feature = MODULE_FEATURE[mod]
      feature.nil? || account.feature_enabled?(feature)
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
