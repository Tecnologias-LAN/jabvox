# frozen_string_literal: true

# Resolver de plantillas SEGURO (sin eval). Contrato de referencias INVIOLABLE:
#   {{trigger.<path>}} {{vars.<name>}} {{global.<key>}} {{item.<path>}}
#   {{bucle.<clave>}}  {{node.<id>.output.*}} {{node.<id>.meta.*}}
#   {{node.<id>.items}} {{node.<id>.raw.*}}
# Si el string es EXACTAMENTE una plantilla, se devuelve el valor con su tipo
# original; con texto mezclado se interpola como string.
module Jabvox::Flows::Engine::Template
  TEMPLATE_RE = /\{\{\s*([^}]+?)\s*\}\}/
  FULL_TEMPLATE_RE = /\A\{\{\s*([^}]+?)\s*\}\}\z/

  module_function

  # Vista de ctx.outputs construida con la PROYECCIÓN ÚNICA.
  def node_scope(outputs, items_path_by_node = {})
    outputs.each_with_object({}) do |(id, raw), view|
      view[id] = Jabvox::Flows::Engine::NodeOutput.project_reference(raw, items_path_by_node[id])
    end
  end

  # Alcance del bucle: `{{item.*}}` más `{{bucle.*}}`. El nombre de la variable
  # del elemento es configurable, así que también se publica bajo su clave.
  def loop_scope(ctx)
    loop = ctx.loop_scope
    return {} if loop.nil?

    scope = { 'item' => loop.item, 'bucle' => loop.counters.to_scope }
    scope[loop.item_var] = loop.item if loop.item_var.present? && loop.item_var != 'item'
    scope
  end

  def scope_for(ctx)
    nodes = node_scope(ctx.outputs, ctx.items_path_by_node)
    # El alcance del bucle va primero para que nunca tape a trigger/vars/node.
    loop_scope(ctx).merge(
      'trigger' => ctx.trigger, 'vars' => ctx.vars,
      'global' => ctx.globals, 'globals' => ctx.globals,
      'node' => nodes, 'outputs' => nodes
    )
  end

  # Accede a una ruta con puntos y corchetes ("a.b[0].c") de forma segura.
  def get_by_path(root, path)
    segments = path.to_s.gsub(/\[(\d+)\]/, '.\1').split('.').map(&:strip).reject(&:empty?)
    segments.reduce(root) do |current, seg|
      case current
      when Hash then current[seg]
      when Array then seg.match?(/\A\d+\z/) ? current[seg.to_i] : nil
      else return nil
      end
    end
  end

  def stringify(value)
    case value
    when nil then ''
    when String then value
    when Hash, Array then value.to_json
    else value.to_s
    end
  end

  # Resuelve plantillas en un valor, recorriendo objetos y arrays.
  def resolve(value, ctx)
    case value
    when String then resolve_string(value, ctx)
    when Array then value.map { |v| resolve(v, ctx) }
    when Hash then value.transform_values { |v| resolve(v, ctx) }
    else value
    end
  end

  def resolve_string(input, ctx)
    scope = scope_for(ctx)
    full = input.match(FULL_TEMPLATE_RE)
    # Plantilla única → preservar tipo original.
    return get_by_path(scope, full[1]) if full

    input.gsub(TEMPLATE_RE) { stringify(get_by_path(scope, Regexp.last_match(1).strip)) }
  end
end
