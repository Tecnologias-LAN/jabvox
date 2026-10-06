require 'rails_helper'

describe Jabvox::Analytics::QueryBuilderService do
  # Doble del adapter: comillas de MySQL, que es el motor de las fuentes con JOIN.
  let(:adapter) do
    Class.new do
      def dialect = :mysql

      def quote_identifier(name)
        name.to_s.gsub(/[^a-zA-Z0-9_.]/, '').split('.').map { |p| "`#{p}`" }.join('.')
      end
    end.new
  end

  def build(spec)
    described_class.new(adapter, spec).build
  end

  describe 'joins' do
    let(:spec) do
      {
        table: 'pedidos',
        columns: ['clientes.ciudad'],
        aggregations: [{ fn: 'count', alias: 'total' }],
        joins: [{ table: 'clientes', on: 'clientes.id = pedidos.cliente_id' }],
        group_by: 'clientes.ciudad'
      }
    end

    it 'une la tabla y cita cada identificador' do
      sql, = build(spec)
      expect(sql).to include('INNER JOIN `clientes` ON `clientes`.`id` = `pedidos`.`cliente_id`')
    end

    it 'soporta LEFT JOIN' do
      sql, = build(spec.merge(joins: [spec[:joins].first.merge(type: 'left')]))
      expect(sql).to include('LEFT JOIN `clientes`')
    end

    it 'cae a INNER ante un tipo desconocido, sin interpolarlo' do
      sql, = build(spec.merge(joins: [spec[:joins].first.merge(type: 'CROSS')]))
      expect(sql).to include('INNER JOIN')
      expect(sql).not_to include('CROSS')
    end

    it 'permite filtrar por una columna de la tabla unida, con bind' do
      sql, binds = build(spec.merge(filters: [{ field: 'clientes.ciudad', operator: 'eq', value: 'Medellín' }]))
      expect(sql).to include('WHERE `clientes`.`ciudad` = ?')
      expect(binds).to eq(['Medellín'])
    end

    # El riesgo real: que la condición ON sirva de vía de inyección, porque es lo único
    # del spec que no pasa por un bind.
    it 'rechaza una condición ON que no sea tabla.columna' do
      ['clientes.id = 1 OR 1=1 --', 'clientes.id = (SELECT 1)', 'clientes.id', ''].each do |mala|
        expect { build(spec.merge(joins: [{ table: 'clientes', on: mala }])) }
          .to raise_error(described_class::InvalidSpec), "aceptó: #{mala.inspect}"
      end
    end

    it 'rechaza un nombre de tabla con caracteres extraños' do
      expect { build(spec.merge(joins: [{ table: 'clientes; DROP TABLE x', on: 'clientes.id = pedidos.cliente_id' }])) }
        .to raise_error(described_class::InvalidSpec)
    end

    it 'ignora un join sin tabla en vez de generar SQL roto' do
      sql, = build(spec.merge(joins: [{ table: '', on: 'a.b = c.d' }]))
      expect(sql).not_to include('JOIN')
    end
  end
end
