# frozen_string_literal: true

# Base de un handler de nodo. El motor invoca `call(ctx, node, params)` con los
# params YA resueltos (Template.resolve), así que aquí nunca se re-resuelve.
class Jabvox::Flows::Nodes::Base
  include Jabvox::Flows::Nodes::Params

  # Metadatos que el registro necesita del catálogo. Los subclases los declaran.
  class << self
    attr_reader :node_type, :node_label, :node_items_path, :node_outputs

    def type(value)
      @node_type = value
    end

    def label(value)
      @node_label = value
    end

    # Ruta de la COLECCIÓN en la salida. Sin esto `{{node.<id>.items}}` no
    # resuelve y el bucle recibe el payload entero como un solo elemento.
    def items_path(value)
      @node_items_path = value
    end

    def outputs(*values)
      @node_outputs = values.flatten
    end

    # Tipos ANTIGUOS que este nodo sigue atendiendo. Renombrar un tipo dejaría rotas las
    # automatizaciones ya guardadas, que llevan el nombre viejo dentro de su grafo: el alias
    # las mantiene funcionando mientras las nuevas se construyen con el nombre actual.
    def aliases(*values)
      @node_aliases = values.flatten
    end

    def node_aliases
      @node_aliases || []
    end

    # Registra el tipo (y sus alias) en un Engine::Registry.
    def register_on(registry)
      ([@node_type] + node_aliases).each do |type|
        registry.register(type, handler: method(:call), items_path: @node_items_path,
                                outputs: @node_outputs || [], label: @node_label)
      end
    end

    def call(ctx, node, params)
      new(ctx, node, params).call
    end
  end

  attr_reader :ctx, :node, :params

  def initialize(ctx, node, params)
    @ctx = ctx
    @node = node
    @params = params.is_a?(Hash) ? params : {}
  end

  # Los subclases implementan `perform` y devuelven el payload o un NodeResult.
  def call
    result = perform
    result.is_a?(Jabvox::Flows::Engine::NodeResult) ? result : ok(result)
  rescue Jabvox::Flows::Engine::ExecutionError => e
    failure(e.message)
  end

  private

  def ok(output, output_port: nil, wait: nil)
    Jabvox::Flows::Engine::NodeResult.ok(output, output_port: output_port, wait: wait)
  end

  def failure(message)
    Jabvox::Flows::Engine::NodeResult.failure(message)
  end

  def param(key)
    @params[key.to_s]
  end

  # Cuenta del run. Multi-tenant estricto: todo nodo opera dentro de ella.
  def account
    @account ||= Account.find(ctx.account_id)
  end

  def fail_with!(message)
    raise Jabvox::Flows::Engine::ExecutionError, message
  end
end
