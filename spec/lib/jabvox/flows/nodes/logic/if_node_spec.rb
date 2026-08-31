# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Nodos de LÓGICA. Se ejercitan por el mismo camino que usa el motor.
RSpec.describe Jabvox::Flows::Nodes::Logic::IfNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  describe Jabvox::Flows::Nodes::Logic::IfNode do
    it 'sale por «true» cuando la condición se cumple' do
      result = run_node(described_class, ctx, { 'left' => '10', 'operator' => 'greater_than', 'right' => '5' })

      expect(result).to be_ok
      expect(result.output_port).to eq('true')
      expect(result.output['result']).to be(true)
    end

    it 'sale por «false» y omite el lado derecho en los operadores unarios' do
      result = run_node(described_class, ctx, { 'left' => 'algo', 'operator' => 'is_empty', 'right' => 'x' })

      expect(result.output_port).to eq('false')
      expect(result.output).not_to have_key('right')
    end
  end

  describe Jabvox::Flows::Nodes::Logic::SetVariableNode do
    it 'publica la variable en el contexto para los pasos siguientes' do
      result = run_node(described_class, ctx, { 'name' => 'total', 'value' => 42 })

      expect(result).to be_ok
      expect(ctx.vars['total']).to eq(42)
    end

    it 'falla si no se le da nombre a la variable' do
      expect(run_node(described_class, ctx, { 'name' => '  ', 'value' => 1 }).error)
        .to match(/nombre de la variable/)
    end
  end

  describe Jabvox::Flows::Nodes::Logic::LoopNode do
    it 'planifica las iteraciones de una colección' do
      result = run_node(described_class, ctx, { 'items' => [1, 2, 3, 4, 5], 'batchSize' => 2 })

      expect(result.output['count']).to eq(5)
      expect(result.output['plannedIterations']).to eq(3)
    end

    it 'acepta una COLECCIÓN VACÍA sin fallar: cero iteraciones es legítimo' do
      result = run_node(described_class, ctx, { 'items' => [] })

      expect(result).to be_ok
      expect(result.output['count']).to be_zero
    end

    it 'explica cómo pedir la colección cuando se apunta a un campo suelto' do
      ctx.outputs['buscar'] = { 'leads' => [{ 'id' => 1 }] }
      ctx.items_path_by_node['buscar'] = 'leads'
      node = build_node(type: 'logic.loop', params: { 'items' => '{{node.buscar.output.id}}' })

      result = run_node(described_class, ctx, node.params, node: node)

      expect(result).not_to be_ok
      expect(result.error).to include('{{node.buscar.items}}')
    end

    it 'se detiene en vez de truncar en silencio al superar el límite' do
      result = run_node(described_class, ctx, { 'items' => (1..10).to_a, 'maxIterations' => 3 })

      expect(result).not_to be_ok
      expect(result.error).to match(/necesita 10 iteraciones/)
    end
  end

  describe Jabvox::Flows::Nodes::Logic::MergeNode do
    it 'concatena los elementos de todas las ramas respetando su itemsPath' do
      ctx = build_ctx(account, outputs: { 'a' => { 'leads' => [{ 'id' => 1 }] }, 'b' => { 'items' => [{ 'id' => 2 }] } },
                               items_path_by_node: { 'a' => 'leads' },
                               incoming_sources_by_node: { 'm' => %w[a b] })
      node = build_node(id: 'm', type: 'logic.merge', params: {})

      result = run_node(described_class, ctx, {}, node: node)

      expect(result.output['count']).to eq(2)
      expect(result.output['items'].map { |i| i['id'] }).to eq([1, 2])
    end

    it 'fusiona por clave y conserva aparte lo que no la trae' do
      ctx = build_ctx(account, outputs: { 'a' => { 'items' => [{ 'id' => 1, 'x' => 1 }] },
                                          'b' => { 'items' => [{ 'id' => 1, 'y' => 2 }, { 'z' => 3 }] } },
                               incoming_sources_by_node: { 'm' => %w[a b] })
      node = build_node(id: 'm', type: 'logic.merge', params: { 'mode' => 'by_key', 'key' => 'id' })

      result = run_node(described_class, ctx, node.params, node: node)

      expect(result.output['coincidencias']).to eq(1)
      expect(result.output['sinClave']).to eq(1)
      expect(result.output['items'].first).to include('x' => 1, 'y' => 2)
    end

    it 'falla si no tiene ramas de entrada conectadas' do
      node = build_node(id: 'm', type: 'logic.merge', params: {})

      expect(run_node(described_class, ctx, {}, node: node).error).to match(/ramas de entrada/)
    end
  end

  describe Jabvox::Flows::Nodes::Logic::DatetimeNode do
    it 'usa Bogotá cuando la zona llega VACÍA, no UTC' do
      result = run_node(described_class, ctx, { 'timezone' => '', 'format' => 'date' })

      expect(result.output['timezone']).to eq('America/Bogota')
      expect(result.output).not_to have_key('timezoneFallback')
    end

    it 'documenta el fallback a UTC cuando la zona es inválida' do
      result = run_node(described_class, ctx, { 'timezone' => 'Marte/Olympus' })

      expect(result.output['timezone']).to eq('UTC')
      expect(result.output['timezoneFallback']).to include('requested' => 'Marte/Olympus')
    end

    it 'aplica el formato personalizado sin solapar tokens' do
      result = run_node(described_class, ctx, { 'format' => 'custom', 'customFormat' => 'DD/MM/YYYY' })

      expect(result.output['value']).to match(%r{\A\d{2}/\d{2}/\d{4}\z})
    end
  end

  describe Jabvox::Flows::Nodes::Logic::SwitchNode do
    let(:cases) { [{ 'value' => 'a' }, { 'value' => 'b', 'output' => 'bee' }] }

    it 'enruta por el primer caso que casa' do
      result = run_node(described_class, ctx, { 'value' => 'b', 'cases' => cases })

      expect(result.output_port).to eq('bee')
    end

    it 'cae a «default» cuando ningún caso casa' do
      expect(run_node(described_class, ctx, { 'value' => 'z', 'cases' => cases }).output_port).to eq('default')
    end

    it 'acepta los casos como JSON en texto' do
      result = run_node(described_class, ctx, { 'value' => 'a', 'cases' => cases.to_json })

      expect(result.output_port).to eq('case1')
    end
  end

  describe Jabvox::Flows::Nodes::Logic::ExpressionNode do
    it 'evalúa una expresión con plantillas y guarda el resultado' do
      ctx = build_ctx(account, trigger: { 'monto' => 500 })

      result = run_node(described_class, ctx, { 'expression' => '{{trigger.monto}} > 100', 'assignTo' => 'caro' })

      expect(result.output['result']).to be(true)
      expect(ctx.vars['caro']).to be(true)
    end

    it 'inserta el texto interpolado como LITERAL, sin sintaxis viva' do
      ctx = build_ctx(account, trigger: { 'nombre' => "Ana' || true || '" })

      result = run_node(described_class, ctx, { 'expression' => '{{trigger.nombre}} == "Ana"' })

      expect(result.output['result']).to be(false)
    end
  end

  describe Jabvox::Flows::Nodes::Logic::DelayNode do
    it 'SUSPENDE el run cuando la espera es larga, en vez de bloquear el worker' do
      result = run_node(described_class, ctx, { 'ms' => 60_000 })

      expect(result).to be_wait
      expect(result.output['mode']).to eq('suspended')
    end

    it 'resuelve en el sitio una espera corta' do
      result = run_node(described_class, ctx, { 'ms' => 1 })

      expect(result).not_to be_wait
      expect(result.output['mode']).to eq('sync')
    end
  end

  describe Jabvox::Flows::Nodes::Logic::WaitUntilNode do
    it 'suspende hasta la fecha indicada' do
      result = run_node(described_class, ctx, { 'until' => 1.hour.from_now.iso8601 })

      expect(result).to be_wait
      expect(result.output['waited']).to be(true)
    end

    it 'continúa de inmediato si la fecha YA pasó, sin quedar colgado' do
      result = run_node(described_class, ctx, { 'until' => 1.hour.ago.iso8601 })

      expect(result).not_to be_wait
      expect(result.output['waited']).to be(false)
    end
  end

  describe Jabvox::Flows::Nodes::Logic::WaitResponseNode do
    it 'cae al timeout por defecto cuando llega VACÍO, no a "sin vencimiento"' do
      result = run_node(described_class, ctx, { 'timeoutMs' => '' })

      expect(result).to be_wait
      expect(result.output['timeoutMs']).to eq(described_class::DEFAULT_TIMEOUT_MS)
    end
  end
end
