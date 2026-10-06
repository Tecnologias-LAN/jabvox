require 'rails_helper'

# Los marcadores `{{CICLO}}` del SQL libre son la única forma de filtrar un widget cuyo SQL
# no declara tabla. Se sustituyen por binds: el valor del filtro nunca entra al texto SQL.
describe Jabvox::Analytics::QueryExecutionService do
  let(:service) { described_class.allocate }

  before { service.instance_variable_set(:@adapter, instance_double(Jabvox::Analytics::Adapters::MysqlAdapter, dialect: :mysql)) }

  def bind(sql, params)
    service.send(:bind_placeholders, sql, params)
  end

  it 'reemplaza el marcador por un placeholder y saca el valor a los binds' do
    sql, binds = bind('SELECT 1 WHERE f.name = {{CICLO}}', { 'CICLO' => '202613' })
    expect(sql).to eq('SELECT 1 WHERE f.name = ?')
    expect(binds).to eq(['202613'])
  end

  it 'nunca mete el valor en el texto, ni cuando trae comillas' do
    sql, binds = bind('SELECT 1 WHERE f.name = {{CICLO}}', { 'CICLO' => "x' OR '1'='1" })
    expect(sql).not_to include('OR')
    expect(binds).to eq(["x' OR '1'='1"])
  end

  it 'numera los binds en orden y admite varios marcadores' do
    sql, binds = bind('... {{A}} ... {{B}} ...', { 'A' => 1, 'B' => 2 })
    expect(sql).to eq('... ? ... ? ...')
    expect(binds).to eq([1, 2])
  end

  it 'acepta claves símbolo' do
    _, binds = bind('{{CICLO}}', { CICLO: '202615' })
    expect(binds).to eq(['202615'])
  end

  it 'usa $n en postgres' do
    service.instance_variable_set(:@adapter, instance_double(Jabvox::Analytics::Adapters::PostgresAdapter, dialect: :postgres))
    sql, = bind('{{A}} {{B}}', { 'A' => 1, 'B' => 2 })
    expect(sql).to eq('$1 $2')
  end

  # Si un marcador sin valor se borrara, la consulta correría sin filtro y mostraría todos
  # los ciclos como si fueran el elegido: un error silencioso peor que uno visible.
  it 'deja intacto el marcador sin valor, para que falle a la vista' do
    sql, binds = bind('WHERE a = {{SIN_VALOR}}', {})
    expect(sql).to include('{{SIN_VALOR}}')
    expect(binds).to be_empty
  end
end
