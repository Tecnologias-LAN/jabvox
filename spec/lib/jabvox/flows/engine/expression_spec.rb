# frozen_string_literal: true

require 'rails_helper'

# Intérprete ACOTADO: sin eval. Debe resolver el mismo scope que las plantillas.
RSpec.describe Jabvox::Flows::Engine::Expression do
  let(:ctx) do
    context = build_context(trigger: { 'tipo' => 'lead' }, vars: { 'x' => 10, 'nombre' => 'Ana' },
                            globals: { 'limite' => '100' },
                            items_path_by_node: { 'busqueda' => 'leads' })
    context.outputs['busqueda'] = { 'leads' => [{ 'id' => 1, 'puntos' => 250 }], 'total' => 1 }
    context
  end

  def evaluate(expression)
    described_class.evaluate(expression, ctx)
  end

  describe 'literales y aritmética' do
    it 'evalúa números, textos y booleanos' do
      expect(evaluate('42')).to eq(42)
      expect(evaluate("'hola'")).to eq('hola')
      expect(evaluate('true')).to be(true)
      expect(evaluate('null')).to be_nil
    end

    it 'respeta la precedencia y los paréntesis' do
      expect(evaluate('2 + 3 * 4')).to eq(14)
      expect(evaluate('(2 + 3) * 4')).to eq(20)
      expect(evaluate('-5 + 2')).to eq(-3)
    end

    it 'concatena si algún operando es texto' do
      expect(evaluate("'total: ' + 5")).to eq('total: 5')
    end
  end

  describe 'referencias del contexto' do
    it 'resuelve vars, trigger y global' do
      expect(evaluate('vars.x')).to eq(10)
      expect(evaluate("trigger.tipo == 'lead'")).to be(true)
      # Sin `global` en el scope, `global.limite > 100` daba false en silencio.
      expect(evaluate('global.limite > 50')).to be(true)
    end

    it 'resuelve node.<id>.output con la proyección única' do
      expect(evaluate('node.busqueda.output.puntos')).to eq(250)
      expect(evaluate('node.busqueda.meta.total')).to eq(1)
    end
  end

  describe 'comparaciones y lógica' do
    it 'evalúa comparaciones e igualdad laxa' do
      expect(evaluate('vars.x > 5')).to be(true)
      expect(evaluate("vars.x == '10'")).to be(true)
      expect(evaluate("vars.x === '10'")).to be(false)
    end

    it 'evalúa && y ||' do
      expect(evaluate('vars.x > 5 && vars.x < 20')).to be(true)
      expect(evaluate('vars.x > 100 || vars.x == 10')).to be(true)
    end

    it 'soporta el operador contains' do
      expect(evaluate("vars.nombre contains 'An'")).to be(true)
    end
  end

  describe 'seguridad' do
    it 'no ejecuta código Ruby arbitrario' do
      expect { evaluate('`whoami`') }.to raise_error(described_class::Error)
      expect { evaluate('system("ls")') }.to raise_error(described_class::Error)
    end

    it 'rechaza expresiones mal formadas' do
      expect { evaluate('2 +') }.to raise_error(described_class::Error)
      expect { evaluate('(2 + 3') }.to raise_error(described_class::Error)
    end
  end
end
