require 'rails_helper'

# Regla de seguridad: los fallos de CONSULTA se explican al usuario (si no, no puede
# arreglarlos), pero los de conexión NO, porque su mensaje lleva usuario, host o topología.
describe Jabvox::Analytics::DbErrorMessage do
  def message_for(text)
    described_class.new(StandardError.new(text)).call
  end

  context 'con un fallo de la consulta' do
    it 'explica un error de sintaxis' do
      result = message_for('PG::SyntaxError: ERROR:  syntax error at or near ";"')
      expect(result).to include('syntax error')
    end

    it 'explica una columna inexistente' do
      result = message_for("Mysql2::Error: Unknown column 'lc.documento_x' in 'field list'")
      expect(result).to include('Unknown column')
    end

    it 'explica una tabla inexistente' do
      result = message_for('PG::UndefinedTable: ERROR:  relation "leads_cstm" does not exist')
      expect(result).to include('does not exist')
    end

    it 'explica un tiempo de espera agotado' do
      expect(message_for('Mysql2::Error::TimeoutError: Timeout waiting')).to include('Timeout')
    end
  end

  context 'con un fallo de conexión' do
    it 'NO filtra el usuario de la base' do
      result = message_for('PG::ConnectionBad: FATAL: password authentication failed for user "admin"')
      expect(result).to eq(described_class::GENERIC)
      expect(result).not_to include('admin')
    end

    it 'NO filtra el host ni el puerto' do
      result = message_for('Errno::ECONNREFUSED: Connection refused - connect(2) for 10.0.0.5:5432')
      expect(result).to eq(described_class::GENERIC)
      expect(result).not_to include('10.0.0.5')
    end
  end

  it 'recorta un mensaje muy largo' do
    expect(message_for("syntax error #{'x' * 500}").length).to be <= 240
  end
end
