# frozen_string_literal: true

# Utilidades compartidas por los specs de nodos: construyen el contexto y el
# nodo del grafo sin arrancar un run completo, que es lo que se prueba aparte.
module NodeSpecHelpers
  def build_ctx(account, **options)
    ctx = Jabvox::Flows::Engine::Context.new(
      account_id: account.id, run_id: 1,
      trigger: options[:trigger] || {}, vars: options[:vars] || {},
      items_path_by_node: options[:items_path_by_node] || {},
      incoming_sources_by_node: options[:incoming_sources_by_node] || {}
    )
    (options[:outputs] || {}).each { |id, value| ctx.outputs[id] = value }
    ctx
  end

  def build_node(id: 'n1', type: 'logic.if', params: {})
    Jabvox::Flows::Engine::Graph::Node.new(id: id, type: type, params: params, data: {})
  end

  # Ejecuta un handler tal como lo invoca el motor: params ya resueltos.
  def run_node(klass, ctx, params, node: nil)
    node ||= build_node(type: klass.node_type, params: params)
    klass.call(ctx, node, Jabvox::Flows::Engine::Template.resolve(params, ctx))
  end
end
