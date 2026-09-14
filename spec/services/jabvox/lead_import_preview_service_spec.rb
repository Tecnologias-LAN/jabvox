# frozen_string_literal: true

require 'rails_helper'

describe Jabvox::LeadImportPreviewService do
  let(:account) { create(:account) }

  def preview(rows, country: 'CO')
    described_class.new(account, rows, country_iso: country).call
  end

  it 'clasifica una fila nueva como nueva' do
    result = preview([{ 'name' => 'Ana', 'phone_number' => '3001234567' }])

    expect(result[:counts][:nuevas]).to eq(1)
    expect(result[:rows].first[:phone]).to eq('+573001234567')
    expect(result[:dial_code]).to eq('57')
  end

  it 'marca como duplicada la fila cuyo teléfono ya existe en la cuenta' do
    existing = create(:contact, account: account, phone_number: '+573001234567')

    result = preview([{ 'name' => 'Ana', 'phone_number' => '3001234567' }])

    expect(result[:counts][:duplicadas_bd]).to eq(1)
    expect(result[:rows].first[:existing_contact_id]).to eq(existing.id)
  end

  it 'marca como duplicada la fila cuyo correo ya existe' do
    create(:contact, account: account, email: 'ana@example.com')

    result = preview([{ 'name' => 'Ana', 'email' => 'ANA@example.com' }])

    expect(result[:counts][:duplicadas_bd]).to eq(1)
  end

  it 'no considera duplicado un número que difiere en un dígito' do
    create(:contact, account: account, phone_number: '+573001234567')

    result = preview([{ 'name' => 'Ana', 'phone_number' => '3001234568' }])

    expect(result[:counts][:nuevas]).to eq(1)
    expect(result[:counts][:duplicadas_bd]).to eq(0)
  end

  it 'detecta repetidos dentro del mismo archivo y solo cuenta el primero como nuevo' do
    result = preview([
                       { 'name' => 'Ana', 'phone_number' => '3001234567' },
                       { 'name' => 'Ana otra vez', 'phone_number' => '+573001234567' }
                     ])

    expect(result[:counts][:nuevas]).to eq(1)
    expect(result[:counts][:duplicadas_archivo]).to eq(1)
  end

  it 'avisa de las filas que ya traen el prefijo en el archivo' do
    result = preview([{ 'name' => 'Ana', 'phone_number' => '+573001234567' }])

    expect(result[:counts][:con_prefijo]).to eq(1)
    expect(result[:rows].first[:notice]).to eq('prefijo_en_archivo')
  end

  it 'cuenta como inválida la fila sin teléfono ni correo utilizables' do
    result = preview([{ 'name' => 'Sin datos', 'phone_number' => 'abc', 'email' => 'no-es-correo' }])

    expect(result[:counts][:invalidas]).to eq(1)
  end

  it 'no ve contactos de otras cuentas' do
    create(:contact, account: create(:account), phone_number: '+573001234567')

    result = preview([{ 'name' => 'Ana', 'phone_number' => '3001234567' }])

    expect(result[:counts][:nuevas]).to eq(1)
  end

  it 'no escribe nada en base de datos' do
    expect { preview([{ 'name' => 'Ana', 'phone_number' => '3001234567' }]) }
      .not_to change(Contact, :count)
  end
end
