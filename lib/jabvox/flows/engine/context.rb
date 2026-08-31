# frozen_string_literal: true

# Contexto de ejecución de un run. Multi-tenant: siempre lleva account_id.
# Mantiene variables y la salida de cada nodo, para que los params puedan
# interpolar `{{vars.x}}` y `{{node.<id>.output.campo}}`.
class Jabvox::Flows::Engine::Context
  # Contadores del bucle visibles como `{{bucle.<clave>}}` (base 1).
  LoopCounters = Struct.new(:iteracion, :posicion_en_lote, :posicion, :total_elementos,
                            :total_iteraciones, :tamano_lote, :lote, keyword_init: true) do
    # Claves EN ESPAÑOL tal como las ven las plantillas: `{{bucle.posicionEnLote}}`.
    def to_scope
      { 'iteracion' => iteracion, 'posicionEnLote' => posicion_en_lote, 'posicion' => posicion,
        'totalElementos' => total_elementos, 'totalIteraciones' => total_iteraciones,
        'tamanoLote' => tamano_lote, 'lote' => lote }
    end
  end

  # Alcance que `logic.loop` publica dentro de su rama.
  LoopScope = Struct.new(:item, :item_var, :counters, :loop_id, :loop_label, keyword_init: true)

  attr_reader :account_id, :run_id, :trigger, :vars, :globals, :secret_values, :outputs,
              :items_path_by_node, :incoming_sources_by_node, :logger
  attr_accessor :loop_scope

  def initialize(account_id:, run_id:, trigger: {}, vars: {}, globals: {}, secret_values: [],
                 items_path_by_node: {}, incoming_sources_by_node: {}, logger: nil)
    @account_id = account_id
    @run_id = run_id
    @trigger = trigger
    @vars = vars
    @globals = globals
    @secret_values = secret_values
    @outputs = {}
    @items_path_by_node = items_path_by_node
    @incoming_sources_by_node = incoming_sources_by_node
    @logger = logger || Rails.logger
  end

  def items_path_for(node_id)
    @items_path_by_node[node_id]
  end
end
