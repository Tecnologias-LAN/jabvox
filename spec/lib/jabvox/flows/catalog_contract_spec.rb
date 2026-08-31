# frozen_string_literal: true

require 'rails_helper'

# CONTRATO CATÁLOGO <-> HANDLER. El editor dibuja los puertos y ofrece los campos
# arrastrables a partir del catálogo (`outputs`, `itemsPath`, `sampleOutput`). Si el
# catálogo miente, el usuario escribe referencias que resuelven VACÍO o dibuja una
# arista por un puerto que el motor no sigue: el flujo "termina bien" sin hacer nada.
RSpec.describe Jabvox::Flows::Catalog do
  let(:registry) { Jabvox::Flows::Registry.build }

  it 'catálogo y registro conocen exactamente los mismos tipos' do
    expect(described_class.types).to match_array(registry.types)
  end

  # Un tipo del catálogo sin handler resoluble se puede arrastrar pero no ejecutar.
  it 'todo tipo NO disparador tiene handler resoluble' do
    described_class.all.reject { |n| n['type'].start_with?('trigger.') }.each do |node|
      expect(registry.handler(node['type'])).not_to be_nil, "#{node['type']} sin handler"
    end
  end

  # El puerto por defecto sale del PRIMER `outputs` declarado. Declarar ahí los
  # CAMPOS de la salida (status/data/...) cambia el puerto por defecto a 'status'
  # y el motor deja de seguir la arista 'out' que dibuja el editor: parada silenciosa.
  it 'el puerto por defecto del motor coincide con el primer puerto del catálogo' do
    described_class.all.each do |node|
      type = node['type']
      expect(registry.default_port(type)).to eq(Array(node['outputs']).first['id']),
                                             "#{type}: el puerto por defecto no es el del catálogo"
    end
  end

  it 'los puertos declarados en el registro son un subconjunto de los del catálogo' do
    described_class.all.each do |node|
      declared = Array(node['outputs']).pluck('id')
      engine = registry.outputs(node['type'])
      next if engine.empty?

      expect(engine - declared).to be_empty, "#{node['type']}: puertos #{engine.inspect} no están en el catálogo"
    end
  end

  # `itemsPath` dirige `{{node.X.items}}`. Si catálogo y handler no coinciden, el
  # bucle recibe el payload entero como UN elemento en vez de la colección.
  it 'el itemsPath del catálogo coincide con el del handler' do
    described_class.all.each do |node|
      expect(node['itemsPath'].to_s).to eq(registry.items_path(node['type']).to_s),
                                        "#{node['type']}: itemsPath discrepante"
    end
  end

  # El editor ofrece los campos de `sampleOutput`: la colección debe estar ahí.
  it 'todo itemsPath declarado existe como clave en sampleOutput' do
    described_class.all.select { |n| n['itemsPath'].present? }.each do |node|
      sample = node['sampleOutput']
      next unless sample.is_a?(Hash)

      expect(sample).to have_key(node['itemsPath']), "#{node['type']}: itemsPath ausente de sampleOutput"
    end
  end

  it 'los 8 nodos de colección son exactamente los que declaran itemsPath' do
    con_items = described_class.all.select { |n| n['itemsPath'].present? }.pluck('type')
    expect(con_items.size).to eq(8)
    expect(con_items).to match_array(registry.types.select { |t| registry.items_path(t).present? })
  end
end
