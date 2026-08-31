# frozen_string_literal: true

# Aristas de VUELTA al bucle. Cerrar el ciclo "y luego vuelve al bucle" es de lo
# más natural de dibujar y hay flujos guardados que lo tienen: el motor lo trata
# como no-op, así que aquí es un AVISO, nunca un error.
module Jabvox::Flows::Validation::LoopEdges
  module_function

  # Nodos de DENTRO de la rama de `loop_id` con una conexión de vuelta al bucle.
  # El recorrido arranca en el puerto 'loop' y para al volver, igual que el motor.
  def returning_to(graph, loop_id)
    stack = graph.successors(loop_id, 'loop').reject { |id| id == loop_id }
    seen = Set.new([loop_id])
    returning = []
    until stack.empty?
      id = stack.pop
      next if seen.include?(id)

      seen << id
      walk_from(graph, id, loop_id, stack, returning)
    end
    add_self_edge(graph, loop_id, returning)
  end

  def walk_from(graph, id, loop_id, stack, returning)
    graph.outgoing(id).each do |edge|
      # No se sigue: esa arista es el cierre del ciclo, no una continuación.
      next returning << id unless edge.target != loop_id

      stack << edge.target
    end
  end

  # Un bucle conectado a SÍ MISMO también es un retorno redundante.
  def add_self_edge(graph, loop_id, returning)
    self_edge = graph.outgoing(loop_id).any? { |e| e.target == loop_id }
    returning << loop_id if self_edge
    returning.uniq
  end
end
