# frozen_string_literal: true

require 'rails_helper'

# REGRESIÓN: los nodos `integration.*` declaraban `outputs 'status', 'headers', 'data'`
# —los CAMPOS de su salida— pero `outputs` son los PUERTOS, y el primero es el puerto
# por defecto. El motor buscaba sucesores por el puerto 'status' mientras el editor
# dibujaba la arista por 'out': el flujo terminaba en éxito SIN ejecutar el paso
# siguiente. Fallo silencioso, el peor tipo.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Puerto de salida de los nodos de integración' do
  let(:registry) { Jabvox::Flows::Registry.build }

  %w[integration.http_request integration.graphql integration.webhook_out].each do |type|
    it "#{type} sale por el puerto por defecto 'out'" do
      expect(registry.default_port(type)).to eq('out')
    end
  end

  it 'el paso siguiente a una petición HTTP SÍ se ejecuta' do
    registry.register('integration.http_request',
                      handler: lambda { |_ctx, _node, _params|
                        Jabvox::Flows::Engine::NodeResult.ok({ 'status' => 200, 'data' => {} })
                      },
                      outputs: registry.outputs('integration.http_request'),
                      label: registry.label('integration.http_request'))

    graph = Jabvox::Flows::Engine::Graph.normalize(
      'nodes' => [
        { 'id' => 't1', 'type' => 'trigger.manual', 'params' => {} },
        { 'id' => 'h1', 'type' => 'integration.http_request', 'params' => { 'url' => 'https://x.test' } },
        { 'id' => 's1', 'type' => 'logic.set_variable', 'params' => { 'name' => 'v', 'value' => 'ok' } }
      ],
      'edges' => [
        { 'id' => 'e0', 'source' => 't1', 'target' => 'h1' },
        { 'id' => 'e1', 'source' => 'h1', 'target' => 's1', 'sourceHandle' => 'out' }
      ]
    )
    ctx = Jabvox::Flows::Engine::Context.new(account_id: 1, run_id: 1, trigger: {}, vars: {},
                                             items_path_by_node: {}, incoming_sources_by_node: {})

    Jabvox::Flows::Engine::Executor.new(graph: graph, ctx: ctx, registry: registry)
                                   .run(trigger_type: 'trigger.manual')

    expect(ctx.outputs.keys).to include('s1')
  end
end
# rubocop:enable RSpec/DescribeClass
