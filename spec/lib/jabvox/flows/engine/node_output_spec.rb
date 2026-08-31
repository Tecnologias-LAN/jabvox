# frozen_string_literal: true

require 'rails_helper'

# PROYECCIÓN ÚNICA: con `itemsPath` declarado, `output` es EL ELEMENTO y los
# metadatos van a `.meta`. Equivocarse aquí genera referencias que no resuelven.
RSpec.describe Jabvox::Flows::Engine::NodeOutput do
  let(:payload) do
    { 'leads' => [{ 'id' => 1, 'contact' => { 'name' => 'Ana' } }, { 'id' => 2 }],
      'total' => 2, 'pagina' => 1 }
  end

  describe '.describe' do
    it 'separa elementos de metadatos cuando itemsPath resuelve' do
      shape = described_class.describe(payload, 'leads')

      expect(shape[:item_count]).to eq(2)
      expect(shape[:items_path_resolved]).to be(true)
      # Metadatos = claves de primer nivel que NO son la colección.
      expect(shape[:metadata]).to eq({ 'total' => 2, 'pagina' => 1 })
    end

    it 'trata el payload entero como UN elemento sin itemsPath' do
      shape = described_class.describe({ 'id' => 7 })

      expect(shape[:items]).to eq([{ 'id' => 7 }])
      expect(shape[:items_path_resolved]).to be(false)
    end

    it 'se degrada a un solo elemento si itemsPath no resuelve a un array' do
      shape = described_class.describe({ 'leads' => 'nada' }, 'leads')

      expect(shape[:item_count]).to eq(1)
      expect(shape[:items_path_resolved]).to be(false)
    end

    it 'cuenta los campos de PRIMER NIVEL del elemento, no las hojas del payload' do
      shape = described_class.describe(payload, 'leads')

      # El elemento de muestra tiene `id` y `contact`: 2 campos, no 3 hojas.
      expect(shape[:field_count]).to eq(2)
      expect(shape[:fields_of_item].map { |f| f[:path] }).to include('contact.name')
    end
  end

  describe '.project_reference' do
    it 'expone output como EL ELEMENTO y los metadatos en meta' do
      view = described_class.project_reference(payload, 'leads')

      expect(view['output']).to eq({ 'id' => 1, 'contact' => { 'name' => 'Ana' } })
      expect(view['meta']).to eq({ 'total' => 2, 'pagina' => 1 })
      expect(view['items'].length).to eq(2)
      expect(view['raw']).to eq(payload)
    end

    it 'mantiene accesibles los campos crudos por compatibilidad' do
      view = described_class.project_reference(payload, 'leads')

      # Los flujos guardados que usan `{{node.<id>.total}}` no se rompen.
      expect(view['total']).to eq(2)
    end

    it 'devuelve el payload entero como output en un nodo de acción simple' do
      view = described_class.project_reference({ 'ok' => true, 'id' => 9 })

      expect(view['output']).to eq({ 'ok' => true, 'id' => 9 })
    end
  end
end
