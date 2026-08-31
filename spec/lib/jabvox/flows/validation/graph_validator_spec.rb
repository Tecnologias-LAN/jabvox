# frozen_string_literal: true

require 'rails_helper'

# Cada regla de validación con un grafo que la VIOLA y otro que NO.
RSpec.describe Jabvox::Flows::Validation::GraphValidator do
  let(:codes) { Jabvox::Flows::Validation::Codes }

  # Registro de prueba con params declarados, para las reglas de completitud.
  let(:registry) do
    registry = Jabvox::Flows::Registry.build
    registry.register('test.envio', label: 'Envío', params: [
                        { 'key' => 'destino', 'label' => 'Destino', 'required' => true },
                        { 'key' => 'modo', 'label' => 'Modo', 'default' => 'simple' },
                        { 'key' => 'plantilla', 'label' => 'Plantilla', 'required' => true,
                          'visibleWhen' => { 'param' => 'modo', 'values' => ['avanzado'] } }
                      ])
    registry.register('logic.switch', label: 'Bifurcación', outputs: %w[default])
    registry
  end

  def validate(graph, mode: :strict)
    described_class.call(graph, mode: mode, registry: registry)
  end

  def codes_of(result)
    result.issues.map(&:code)
  end

  # Grafo mínimo correcto: disparador → envío configurado.
  def valid_graph
    { 'nodes' => [
        { 'id' => 't', 'type' => 'trigger.manual' },
        { 'id' => 'e', 'type' => 'test.envio', 'params' => { 'destino' => 'x@y.z' } }
      ],
      'edges' => [{ 'id' => 'e1', 'source' => 't', 'target' => 'e' }] }
  end

  it 'acepta un grafo correcto sin ningún problema' do
    result = validate(valid_graph)

    expect(result).to be_valid
    expect(result.issues).to be_empty
  end

  describe 'GRAPH_MALFORMED' do
    it 'rechaza un grafo sin listas de pasos y conexiones' do
      expect(codes_of(validate({ 'nodes' => 'no soy una lista' }))).to include(codes::GRAPH_MALFORMED)
    end

    it 'acepta un grafo con ambas listas presentes' do
      expect(codes_of(validate({ 'nodes' => [], 'edges' => [] }))).not_to include(codes::GRAPH_MALFORMED)
    end
  end

  describe 'NODE_MISSING_ID_OR_TYPE' do
    it 'rechaza un paso sin tipo' do
      graph = { 'nodes' => [{ 'id' => 'x' }], 'edges' => [] }

      expect(codes_of(validate(graph))).to include(codes::NODE_MISSING_ID_OR_TYPE)
    end

    it 'acepta pasos con id y tipo' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::NODE_MISSING_ID_OR_TYPE)
    end
  end

  describe 'NODE_DUPLICATE_ID' do
    it 'rechaza dos pasos con el mismo id' do
      graph = valid_graph
      graph['nodes'] << { 'id' => 'e', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }

      expect(codes_of(validate(graph))).to include(codes::NODE_DUPLICATE_ID)
    end

    it 'acepta ids únicos' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::NODE_DUPLICATE_ID)
    end
  end

  describe 'NODE_UNKNOWN_TYPE' do
    it 'rechaza un tipo que no está en el catálogo' do
      graph = valid_graph
      graph['nodes'] << { 'id' => 'z', 'type' => 'inventado.tipo' }

      expect(codes_of(validate(graph))).to include(codes::NODE_UNKNOWN_TYPE)
    end

    it 'acepta los tipos registrados' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::NODE_UNKNOWN_TYPE)
    end
  end

  describe 'EDGE_DANGLING' do
    it 'rechaza una conexión hacia un paso inexistente' do
      graph = valid_graph
      graph['edges'] << { 'id' => 'e2', 'source' => 'e', 'target' => 'fantasma' }

      expect(codes_of(validate(graph))).to include(codes::EDGE_DANGLING)
    end

    it 'acepta conexiones entre pasos existentes' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::EDGE_DANGLING)
    end
  end

  describe 'EDGE_INVALID_SOURCE_HANDLE' do
    # Es lo que PROTEGE los puertos loop/done del bucle.
    it 'rechaza un puerto de salida no declarado por el tipo' do
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 'b', 'type' => 'logic.loop', 'params' => { 'items' => '{{trigger.items}}' } },
                  { 'id' => 'f', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
                ],
                'edges' => [
                  { 'id' => 'e1', 'source' => 't', 'target' => 'b' },
                  { 'id' => 'e2', 'source' => 'b', 'target' => 'f', 'sourceHandle' => 'inventado' }
                ] }
      result = validate(graph)

      expect(codes_of(result)).to include(codes::EDGE_INVALID_SOURCE_HANDLE)
      expect(result.issues.find { |i| i.code == codes::EDGE_INVALID_SOURCE_HANDLE }.message)
        .to include('loop', 'done')
    end

    it 'acepta los puertos loop y done del bucle' do
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 'b', 'type' => 'logic.loop', 'params' => { 'items' => '{{trigger.items}}' } },
                  { 'id' => 'f', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
                ],
                'edges' => [
                  { 'id' => 'e1', 'source' => 't', 'target' => 'b' },
                  { 'id' => 'e2', 'source' => 'b', 'target' => 'f', 'sourceHandle' => 'done' }
                ] }

      expect(codes_of(validate(graph))).not_to include(codes::EDGE_INVALID_SOURCE_HANDLE)
    end

    it 'acepta los puertos DINÁMICOS que el switch deriva de sus casos' do
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 's', 'type' => 'logic.switch',
                    'params' => { 'cases' => [{ 'value' => 'a', 'output' => 'ruta_a' }] } },
                  { 'id' => 'f', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
                ],
                'edges' => [
                  { 'id' => 'e1', 'source' => 't', 'target' => 's' },
                  { 'id' => 'e2', 'source' => 's', 'target' => 'f', 'sourceHandle' => 'ruta_a' }
                ] }

      expect(codes_of(validate(graph))).not_to include(codes::EDGE_INVALID_SOURCE_HANDLE)
    end
  end

  describe 'PARAM_REQUIRED_EMPTY' do
    it 'rechaza un campo obligatorio vacío' do
      graph = valid_graph
      graph['nodes'][1]['params'] = { 'destino' => '  ' }
      result = validate(graph)

      expect(codes_of(result)).to include(codes::PARAM_REQUIRED_EMPTY)
      expect(result.issues.first.param).to eq('destino')
    end

    # 'destino' está relleno, y 'plantilla' solo es visible con modo=avanzado
    # (el default es 'simple'): un obligatorio OCULTO no se exige.
    it 'acepta un obligatorio relleno y no exige el que está oculto' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::PARAM_REQUIRED_EMPTY)
    end

    it 'SÍ exige ese obligatorio cuando la condición lo hace visible' do
      graph = valid_graph
      graph['nodes'][1]['params'] = { 'destino' => 'a', 'modo' => 'avanzado' }
      result = validate(graph)

      expect(result.issues.map(&:param)).to include('plantilla')
    end

    it 'no considera vacío un false ni un cero' do
      registry.register('test.flag', label: 'Bandera',
                                     params: [{ 'key' => 'activo', 'label' => 'Activo', 'required' => true }])
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 'f', 'type' => 'test.flag', 'params' => { 'activo' => false } }
                ],
                'edges' => [{ 'id' => 'e1', 'source' => 't', 'target' => 'f' }] }

      expect(codes_of(validate(graph))).not_to include(codes::PARAM_REQUIRED_EMPTY)
    end
  end

  describe 'TEMPLATE_UNKNOWN_NODE' do
    it 'rechaza una referencia a un paso que no existe' do
      graph = valid_graph
      graph['nodes'][1]['params'] = { 'destino' => '{{node.fantasma.output.email}}' }
      result = validate(graph)

      expect(codes_of(result)).to include(codes::TEMPLATE_UNKNOWN_NODE)
      expect(result.issues.first.param).to eq('destino')
    end

    it 'acepta una referencia a un paso presente en el grafo' do
      graph = valid_graph
      graph['nodes'][1]['params'] = { 'destino' => '{{node.t.output.email}}' }

      expect(codes_of(validate(graph))).not_to include(codes::TEMPLATE_UNKNOWN_NODE)
    end
  end

  describe 'FLOW_NO_TRIGGER' do
    it 'rechaza un flujo sin ningún disparador' do
      graph = { 'nodes' => [{ 'id' => 'e', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }],
                'edges' => [] }

      expect(codes_of(validate(graph))).to include(codes::FLOW_NO_TRIGGER)
    end

    it 'acepta un flujo con disparador' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::FLOW_NO_TRIGGER)
    end

    it 'no se queja de un grafo completamente vacío' do
      expect(codes_of(validate({ 'nodes' => [], 'edges' => [] }))).to be_empty
    end
  end

  describe 'FLOW_DUPLICATE_TRIGGER' do
    it 'rechaza dos disparadores del mismo tipo' do
      graph = valid_graph
      graph['nodes'] << { 'id' => 't2', 'type' => 'trigger.manual' }
      graph['edges'] << { 'id' => 'e2', 'source' => 't2', 'target' => 'e' }

      expect(codes_of(validate(graph))).to include(codes::FLOW_DUPLICATE_TRIGGER)
    end

    it 'acepta dos disparadores de tipos DISTINTOS' do
      graph = valid_graph
      graph['nodes'] << { 'id' => 't2', 'type' => 'trigger.webhook' }
      graph['edges'] << { 'id' => 'e2', 'source' => 't2', 'target' => 'e' }

      expect(codes_of(validate(graph))).not_to include(codes::FLOW_DUPLICATE_TRIGGER)
    end
  end

  describe 'NODE_ORPHAN (aviso)' do
    it 'avisa de un paso sin conexión de entrada, sin bloquear' do
      graph = valid_graph
      graph['nodes'] << { 'id' => 'suelto', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
      result = validate(graph)

      expect(codes_of(result)).to include(codes::NODE_ORPHAN)
      expect(result.warnings.map(&:code)).to include(codes::NODE_ORPHAN)
      expect(result).to be_valid
    end

    it 'no considera huérfano a un disparador' do
      expect(codes_of(validate(valid_graph))).not_to include(codes::NODE_ORPHAN)
    end
  end

  describe 'LOOP_REDUNDANT_BACK_EDGE (aviso, NUNCA error)' do
    # El usuario TIENE un flujo guardado con esta arista: convertirla en error
    # le impediría guardar.
    let(:graph_con_vuelta) do
      { 'nodes' => [
          { 'id' => 't', 'type' => 'trigger.manual' },
          { 'id' => 'b', 'type' => 'logic.loop', 'params' => { 'items' => '{{trigger.items}}' } },
          { 'id' => 'cuerpo', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
        ],
        'edges' => [
          { 'id' => 'e1', 'source' => 't', 'target' => 'b' },
          { 'id' => 'e2', 'source' => 'b', 'target' => 'cuerpo', 'sourceHandle' => 'loop' },
          { 'id' => 'e3', 'source' => 'cuerpo', 'target' => 'b' }
        ] }
    end

    it 'avisa de la arista de vuelta al bucle SIN invalidar el flujo' do
      result = validate(graph_con_vuelta)

      issue = result.issues.find { |i| i.code == codes::LOOP_REDUNDANT_BACK_EDGE }
      expect(issue).to be_present
      expect(issue).to be_warning
      expect(issue.node_id).to eq('cuerpo')
      # Lo crítico: el flujo del usuario SE PUEDE GUARDAR Y ACTIVAR.
      expect(result).to be_valid
      expect(result.blocking).to be_empty
    end

    it 'no avisa cuando la rama del bucle no vuelve a él' do
      graph = graph_con_vuelta
      graph['edges'].pop

      expect(codes_of(validate(graph))).not_to include(codes::LOOP_REDUNDANT_BACK_EDGE)
    end

    it 'avisa también del bucle conectado a SÍ MISMO' do
      graph = graph_con_vuelta
      graph['edges'] << { 'id' => 'e4', 'source' => 'b', 'target' => 'b', 'sourceHandle' => 'loop' }
      result = validate(graph)

      expect(result.issues.select { |i| i.code == codes::LOOP_REDUNDANT_BACK_EDGE }.map(&:node_id))
        .to include('b')
      expect(result).to be_valid
    end
  end

  describe 'GRAPH_CYCLE' do
    it 'rechaza un ciclo que NO es de bucle' do
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 'a', 'type' => 'test.envio', 'params' => { 'destino' => 'x' } },
                  { 'id' => 'b', 'type' => 'test.envio', 'params' => { 'destino' => 'y' } }
                ],
                'edges' => [
                  { 'id' => 'e1', 'source' => 't', 'target' => 'a' },
                  { 'id' => 'e2', 'source' => 'a', 'target' => 'b' },
                  { 'id' => 'e3', 'source' => 'b', 'target' => 'a' }
                ] }

      expect(codes_of(validate(graph))).to include(codes::GRAPH_CYCLE)
    end

    it 'NO marca como ciclo la iteración normal de un bucle' do
      graph = { 'nodes' => [
                  { 'id' => 't', 'type' => 'trigger.manual' },
                  { 'id' => 'b', 'type' => 'logic.loop', 'params' => { 'items' => '{{trigger.items}}' } },
                  { 'id' => 'cuerpo', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
                ],
                'edges' => [
                  { 'id' => 'e1', 'source' => 't', 'target' => 'b' },
                  { 'id' => 'e2', 'source' => 'b', 'target' => 'cuerpo', 'sourceHandle' => 'loop' },
                  { 'id' => 'e3', 'source' => 'cuerpo', 'target' => 'b' }
                ] }

      expect(codes_of(validate(graph))).not_to include(codes::GRAPH_CYCLE)
    end
  end

  describe 'modos permisivo y estricto' do
    # El editor AUTOGUARDA a media construcción: un obligatorio vacío no puede
    # bloquear el guardado.
    let(:incompleto) do
      graph = valid_graph
      graph['nodes'][1]['params'] = {}
      graph['nodes'] << { 'id' => 'suelto', 'type' => 'test.envio', 'params' => { 'destino' => 'a' } }
      graph
    end

    it 'el permisivo NO se queja de obligatorios vacíos ni de huérfanos' do
      result = validate(incompleto, mode: :permissive)

      expect(codes_of(result)).not_to include(codes::PARAM_REQUIRED_EMPTY)
      expect(codes_of(result)).not_to include(codes::NODE_ORPHAN)
      expect(result.blocking).to be_empty
    end

    it 'el estricto SÍ se queja de lo mismo' do
      result = validate(incompleto, mode: :strict)

      expect(codes_of(result)).to include(codes::PARAM_REQUIRED_EMPTY)
      expect(result).not_to be_valid
    end

    it 'el permisivo SÍ bloquea los problemas estructurales' do
      graph = { 'nodes' => [{ 'id' => 'a', 'type' => 'test.envio' }, { 'id' => 'a', 'type' => 'test.envio' }],
                'edges' => [] }
      result = validate(graph, mode: :permissive)

      expect(result.blocking.map(&:code)).to include(codes::NODE_DUPLICATE_ID)
    end
  end

  describe 'contrato de salida' do
    it 'serializa los issues con los códigos estables' do
      graph = valid_graph
      graph['nodes'][1]['params'] = {}
      hash = validate(graph).to_h

      expect(hash['valid']).to be(false)
      expect(hash['errorCount']).to eq(1)
      expect(hash['issues'].first).to include('code' => 'PARAM_REQUIRED_EMPTY', 'severity' => 'error')
    end
  end
end
