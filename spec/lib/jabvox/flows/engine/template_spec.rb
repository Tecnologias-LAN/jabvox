# frozen_string_literal: true

require 'rails_helper'

# CONTRATO DE DATOS: las expresiones que usan los flujos en producción deben
# seguir resolviendo idénticas. Nada de `$json` ni del formato [{json:{}}].
RSpec.describe Jabvox::Flows::Engine::Template do
  let(:ctx) do
    context = build_context(trigger: { 'evento' => { 'id' => 5 } }, vars: { 'x' => 10 },
                            globals: { 'limite' => '100' },
                            items_path_by_node: { 'busqueda' => 'leads' })
    context.outputs['busqueda'] = { 'leads' => [{ 'id' => 1, 'nombre' => 'Ana' }], 'total' => 1 }
    context.outputs['accion'] = { 'ok' => true }
    context
  end

  describe 'referencias del contrato' do
    it 'resuelve {{trigger.*}}, {{vars.*}} y {{global.*}}' do
      expect(described_class.resolve_string('{{trigger.evento.id}}', ctx)).to eq(5)
      expect(described_class.resolve_string('{{vars.x}}', ctx)).to eq(10)
      expect(described_class.resolve_string('{{global.limite}}', ctx)).to eq('100')
    end

    it 'resuelve {{node.<id>.output.*}} al ELEMENTO cuando hay itemsPath' do
      expect(described_class.resolve_string('{{node.busqueda.output.nombre}}', ctx)).to eq('Ana')
    end

    it 'resuelve {{node.<id>.meta.*}} y {{node.<id>.items}}' do
      expect(described_class.resolve_string('{{node.busqueda.meta.total}}', ctx)).to eq(1)
      expect(described_class.resolve_string('{{node.busqueda.items}}', ctx).length).to eq(1)
    end

    it 'resuelve {{node.<id>.output}} al payload en un nodo de acción simple' do
      expect(described_class.resolve_string('{{node.accion.output.ok}}', ctx)).to be(true)
    end
  end

  describe 'alcance del bucle' do
    before do
      counters = Jabvox::Flows::Engine::Context::LoopCounters.new(
        iteracion: 2, posicion_en_lote: 1, posicion: 2, total_elementos: 3,
        total_iteraciones: 3, tamano_lote: 1, lote: []
      )
      ctx.loop_scope = Jabvox::Flows::Engine::Context::LoopScope.new(
        item: { 'nombre' => 'Beto' }, item_var: 'lead', counters: counters,
        loop_id: 'bucle', loop_label: 'Bucle'
      )
    end

    it 'resuelve {{item.*}} y el alias con el nombre configurado' do
      expect(described_class.resolve_string('{{item.nombre}}', ctx)).to eq('Beto')
      expect(described_class.resolve_string('{{lead.nombre}}', ctx)).to eq('Beto')
    end

    it 'resuelve los contadores {{bucle.*}} en base 1' do
      expect(described_class.resolve_string('{{bucle.iteracion}}', ctx)).to eq(2)
      expect(described_class.resolve_string('{{bucle.totalElementos}}', ctx)).to eq(3)
    end
  end

  describe 'tipos e interpolación' do
    it 'preserva el tipo original con una plantilla única' do
      expect(described_class.resolve_string('{{node.busqueda.items}}', ctx)).to be_an(Array)
      expect(described_class.resolve_string('{{vars.x}}', ctx)).to be_an(Integer)
    end

    it 'interpola como texto cuando hay contenido mezclado' do
      expect(described_class.resolve_string('Lead {{node.busqueda.output.nombre}} (x{{vars.x}})', ctx))
        .to eq('Lead Ana (x10)')
    end

    it 'resuelve una referencia inexistente a cadena vacía al interpolar' do
      expect(described_class.resolve_string('valor: {{vars.no_existe}}', ctx)).to eq('valor: ')
    end

    it 'recorre objetos y arrays anidados' do
      resolved = described_class.resolve({ 'a' => ['{{vars.x}}', { 'b' => '{{item.nombre}}' }] }, ctx)

      expect(resolved).to eq({ 'a' => [10, { 'b' => nil }] })
    end

    it 'soporta índices con corchetes' do
      expect(described_class.resolve_string('{{node.busqueda.items[0].nombre}}', ctx)).to eq('Ana')
    end
  end
end
