# frozen_string_literal: true

# MODELO DE CONFLUENCIA (tokens por arista).
#
# Con BFS puro y un simple `visited`, en un diamante (A→B→D, A→C→D) el nodo D se
# ejecutaba en cuanto llegaba la PRIMERA rama y la segunda se descartaba: con
# ramas de distinta longitud, D corría sin los datos de la rama larga.
#
# Aquí cada nodo ESPERA: solo entra en la cola cuando TODAS sus aristas entrantes
# contadas se han resuelto, cada una como «disparada» (su origen ejecutó y tomó
# ese puerto) o «muerta» (su origen tomó otro puerto, o falló con política
# 'continue'). Un nodo cuyas entradas se resuelven TODAS muertas no se ejecuta y
# propaga «muerta» en cascada — así un IF→merge no se cuelga esperando la rama
# no tomada, y la rama falsa sin conectar no deja el run colgado.
class Jabvox::Flows::Engine::TokenRouter
  attr_reader :queue, :dead_nodes, :visited

  def initialize(graph, analysis)
    @graph = graph
    @analysis = analysis
    @queue = []
    @visited = Set.new
    @dead_nodes = Set.new
    @resolved_count = Hash.new(0)
    @any_fired = {}
    @expected = compute_expected
  end

  def visited?(node_id)
    @visited.include?(node_id)
  end

  def mark_visited(node_id)
    @visited << node_id
  end

  def next_node
    @queue.shift
  end

  def pending?
    @queue.any?
  end

  def seed(node_ids)
    @queue.concat(node_ids)
  end

  # Resuelve TODAS las aristas salientes contadas de un nodo ya procesado.
  # `fired_ports` nil significa que ninguna salida se toma (fallo con 'continue').
  def resolve_outgoing(node_id, fired_ports)
    @graph.outgoing(node_id).each do |edge|
      next unless @analysis.counted?(edge)

      deliver(edge.target, !fired_ports.nil? && fired_ports.include?(edge.port))
    end
  end

  # Entrega el token de una arista contada y encola/mata al destino. La cascada
  # de muerte se procesa iterativamente para no recursar en grafos profundos.
  def deliver(target, fired)
    pending = [{ target: target, fired: fired }]
    until pending.empty?
      delivery = pending.shift
      handle_delivery(delivery, pending)
    end
  end

  private

  def handle_delivery(delivery, pending)
    target = delivery[:target]
    return if @visited.include?(target) || @dead_nodes.include?(target)

    seen = (@resolved_count[target] += 1)
    @any_fired[target] = true if delivery[:fired]
    return if seen < @expected.fetch(target, 0)

    return @queue << target if @any_fired[target]

    kill(target, pending)
  end

  # Todas sus entradas murieron: el nodo no corre y propaga «muerta».
  def kill(target, pending)
    @dead_nodes << target
    @graph.outgoing(target).each do |edge|
      pending << { target: edge.target, fired: false } if @analysis.counted?(edge)
    end
  end

  def compute_expected
    @graph.edges.each_with_object(Hash.new(0)) do |edge, acc|
      acc[edge.target] += 1 if @analysis.counted?(edge)
    end
  end
end
