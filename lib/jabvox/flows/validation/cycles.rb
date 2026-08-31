# frozen_string_literal: true

# Detección de CICLOS que no son de bucle. Un `logic.loop` itera por diseño, así
# que las aristas de su rama y las de vuelta a él no cuentan como ciclo; lo que
# se busca es la realimentación que el motor NO sabe recorrer.
module Jabvox::Flows::Validation::Cycles
  GRAY = 1
  BLACK = 2

  module_function

  # Nodos implicados en un ciclo ajeno a los bucles, sin repetir.
  def detect(graph)
    color = {}
    found = []
    graph.nodes.each { |node| dfs(graph, node.id, color, found) unless color.key?(node.id) }
    found.uniq
  end

  def dfs(graph, root, color, found)
    color[root] = GRAY
    stack = [{ id: root, index: 0 }]
    until stack.empty?
      frame = stack.last
      edges = countable_edges(graph, frame[:id])
      next close_frame(color, stack, frame) if frame[:index] >= edges.length

      edge = edges[frame[:index]]
      frame[:index] += 1
      visit(edge, color, found, stack)
    end
  end

  def close_frame(color, stack, frame)
    color[frame[:id]] = BLACK
    stack.pop
  end

  def visit(edge, color, found, stack)
    case color[edge.target]
    when GRAY then found << edge.target
    when nil
      color[edge.target] = GRAY
      stack << { id: edge.target, index: 0 }
    end
  end

  # Se excluyen la rama 'loop' de un bucle y las vueltas a un bucle: son su
  # forma normal de iterar, no una realimentación rota.
  def countable_edges(graph, node_id)
    graph.outgoing(node_id).reject do |edge|
      (graph.node(edge.source)&.loop? && edge.port == 'loop') || graph.node(edge.target)&.loop?
    end
  end
end
