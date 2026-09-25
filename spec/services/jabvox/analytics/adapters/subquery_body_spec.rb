require 'rails_helper'

# La consulta del usuario se envuelve en `SELECT * FROM (...) AS jabvox_sub` para imponer el
# tope de filas. Un `;` final —que casi todo cliente SQL añade al copiar— dejaba ese
# envoltorio inválido y la base devolvía un error de sintaxis.
describe Jabvox::Analytics::Adapters::BaseAdapter do
  let(:data_source) do
    JabvoxAnalyticsDataSource.new(
      account_id: 1, name_jabvox: 'test', engine_jabvox: 'postgresql',
      host_jabvox: 'localhost', database_jabvox: 'test', max_rows_jabvox: 5000
    )
  end
  let(:adapter) { Jabvox::Analytics::Adapters::PostgresAdapter.new(data_source) }

  def body(sql)
    adapter.send(:subquery_body, sql)
  end

  it 'quita el punto y coma final' do
    expect(body('SELECT 1 FROM t LIMIT 10;')).to eq('SELECT 1 FROM t LIMIT 10')
  end

  it 'quita varios puntos y coma con espacios detrás' do
    expect(body("SELECT 1 FROM t;;  \n ")).to eq('SELECT 1 FROM t')
  end

  it 'quita un comentario final que comentaría el paréntesis de cierre' do
    expect(body("SELECT 1 FROM t\n-- nota final")).to eq('SELECT 1 FROM t')
  end

  it 'quita comentario y punto y coma juntos' do
    expect(body('SELECT 1 FROM t; -- fin')).to eq('SELECT 1 FROM t')
  end

  it 'deja intacta una consulta que ya venía bien' do
    expect(body('SELECT 1 FROM t')).to eq('SELECT 1 FROM t')
  end

  it 'NO toca un punto y coma que va dentro de una cadena' do
    expect(body("SELECT 'a;b' FROM t")).to eq("SELECT 'a;b' FROM t")
  end
end
