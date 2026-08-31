# frozen_string_literal: true

# Análisis estático del grafo para UN recorrido: qué es alcanzable, qué aristas
# son de retroceso y qué nodos son interiores de un bucle. De aquí sale
# `counted?`, que decide qué aristas participan en el modelo de tokens.
class Jabvox::Flows::Engine::GraphAnalysis
  GRAY = 1
  BLACK = 2

  attr_reader :reachable, :back_edges, :loop_internal

  def initialize(graph, roots)
    @graph = graph
    @roots = roots
    @reachable = compute_reachable
    @back_edges = compute_back_edges
    @loop_internal = compute_loop_internal
  end

  # Aristas EXCLUIDAS del conteo (no bloquean ni entregan):
  #  - origen o destino fuera del subgrafo alcanzable desde las raíces;
  #  - aristas de RETROCESO: nunca podrían resolverse antes de que corra su destino;
  #  - la rama 'loop' de un bucle y todo su subgrafo interno, que recorre
  #    `run_loop_branch` con su propia disciplina.
  def counted?(edge)
    @reachable.include?(edge.source) && @reachable.include?(edge.target) &&
      @back_edges.exclude?(edge) &&
      @loop_internal.exclude?(edge.source) && @loop_internal.exclude?(edge.target) &&
      !loop_branch_edge?(edge)
  end

  def loop_branch_edge?(edge)
    @graph.node(edge.source)&.loop? && edge.port == 'loop'
  end

  # Destinos que tienen al menos una arista contada entrante.
  def counted_incoming
    @counted_incoming ||= @graph.edges.select { |e| counted?(e) }.to_set(&:target)
  end

  private

  def compute_reachable
    seen = Set.new(@roots)
    stack = @roots.dup
    until stack.empty?
      id = stack.pop
      @graph.outgoing(id).each do |edge|
        next if seen.include?(edge.target)

        seen << edge.target
        stack << edge.target
      end
    end
    seen
  end

  # Aristas de retroceso: DFS iterativo con coloreado gris/negro.
  def compute_back_edges
    edges = Set.new
    color = {}
    @roots.each { |root| dfs_back_edges(root, color, edges) unless color.key?(root) }
    edges
  end

  def dfs_back_edges(root, color, edges)
    color[root] = GRAY
    stack = [{ id: root, index: 0 }]
    until stack.empty?
      frame = stack.last
      outs = @graph.outgoing(frame[:id])
      if frame[:index] >= outs.length
        color[frame[:id]] = BLACK
        stack.pop
        next
      end
      edge = outs[frame[:index]]
      frame[:index] += 1
      visit_back_edge(edge, color, edges, stack)
    end
  end

  def visit_back_edge(edge, color, edges, stack)
    case color[edge.target]
    when GRAY then edges << edge
    when nil
      color[edge.target] = GRAY
      stack << { id: edge.target, index: 0 }
    end
  end

  # Subgrafo interno de los bucles: lo alcanzable desde el puerto 'loop' de cada
  # bucle, con DOS cortes imprescindibles.
  #
  # BUG QUE ESTO CORRIGE: si el usuario cierra el ciclo dentro de la rama (un
  # paso de dentro vuelve a apuntar al propio bucle — lo natural de dibujar), el
  # PROPIO bucle acababa dentro de su `loop_internal`. Entonces `counted?`
  # descartaba la arista que lo alimenta, sus entradas esperadas quedaban en 0,
  # nunca se encolaba, y el flujo se paraba EN SILENCIO en el paso anterior al
  # bucle con estado de éxito. Por arrastre la rama 'done' tampoco corría.
  #
  # Los cortes:
  #  1. El recorrido PARA al volver al bucle dueño: esa arista es el cierre
  #     natural del ciclo, no una continuación (el bucle ya repite solo).
  #  2. Se recorre POR BUCLE y se acumula: un bucle ANIDADO sí es interno al
  #     padre, por eso el corte 1 es por recorrido (`owner_id`) y no global.
  def compute_loop_internal
    internal = Set.new
    @graph.nodes.each do |node|
      next unless node.loop? && @reachable.include?(node.id)

      collect_loop_internal(node.id, internal)
    end
    internal
  end

  def collect_loop_internal(owner_id, internal)
    stack = @graph.successors(owner_id, 'loop').reject { |id| id == owner_id }
    seen = Set.new([owner_id])
    until stack.empty?
      id = stack.pop
      next if seen.include?(id)

      seen << id
      internal << id
      # Parar en el bucle dueño de ESTE recorrido (cierre del ciclo).
      @graph.outgoing(id).each { |e| stack << e.target unless e.target == owner_id }
    end
  end
end
