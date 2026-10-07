require 'rails_helper'

# Un CSV con su columna de número bien puesta se rechazaba con "El archivo debe tener una
# columna de número": Excel guarda los CSV con BOM —una marca invisible que convertía la
# primera cabecera en "﻿numero"— y en configuración regional española separa con ';',
# con lo que la línea entera se leía como una sola cabecera.
describe Jabvox::BulkWhatsappDispatchService do
  subject(:service) do
    instance = described_class.allocate
    instance.instance_variable_set(:@number_column, nil)
    instance.instance_variable_set(:@country_iso, nil)
    instance
  end

  def parse(raw)
    service.instance_variable_set(:@csv_io, StringIO.new(raw))
    service.send(:parse_rows)
  end

  it 'lee un CSV normal' do
    expect(parse("numero,nombre\n573001112233,Ana\n").first)
      .to include('numero' => '573001112233', 'nombre' => 'Ana')
  end

  it 'lee un CSV guardado por Excel, con BOM' do
    expect(parse("\xEF\xBB\xBFnumero,nombre\n573001112233,Ana\n").first)
      .to include('numero' => '573001112233', 'nombre' => 'Ana')
  end

  it 'lee un CSV separado por punto y coma (Excel en español)' do
    expect(parse("numero;nombre\n573001112233;Ana\n").first)
      .to include('numero' => '573001112233', 'nombre' => 'Ana')
  end

  it 'lee el caso real: BOM y punto y coma a la vez' do
    expect(parse("\xEF\xBB\xBFnumero;nombre\n573001112233;Ana\n").first)
      .to include('numero' => '573001112233', 'nombre' => 'Ana')
  end

  # Los archivos reales no traen la cabecera exacta: vienen "Telefono Celular",
  # "Celular (WhatsApp)" o "Numero de contacto".
  it 'acepta cabeceras que contienen el nombre, no solo las exactas' do
    ['Telefono Celular,Nombre', 'Celular (WhatsApp),Nombre', 'Numero de contacto,Nombre'].each do |cabecera|
      expect(parse("#{cabecera}\n573001112233,Ana\n").first['numero']).to eq('573001112233')
    end
  end

  it 'sigue rechazando un archivo sin columna de número' do
    expect { parse("nombre,correo\nAna,a@b.co\n") }
      .to raise_error(described_class::Error, /columna de número/)
  end
end
