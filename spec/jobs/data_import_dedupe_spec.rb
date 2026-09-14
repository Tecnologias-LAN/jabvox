# frozen_string_literal: true

require 'rails_helper'

# Reglas de identidad del import CSV del dashboard:
#   - El prefijo telefónico sale del país elegido, nunca se adivina del número.
#   - La comparación con lo existente es EXACTA (teléfono o correo).
#   - Un lead que ya existe no se duplica: se actualiza u omite según la política
#     que el usuario confirmó en la vista previa.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Deduplicación del import de contactos por CSV' do
  let(:account) { create(:account) }

  def csv_file(rows)
    file = Tempfile.new(['import', '.csv'])
    CSV.open(file.path, 'w') { |csv| rows.each { |row| csv << row } }
    Rack::Test::UploadedFile.new(file.path, 'text/csv')
  end

  def run_import(rows, country: 'CO', policy: 'skip')
    data_import = create(:data_import, account: account, import_file: csv_file(rows),
                                       source_metadata: { 'country' => country, 'duplicate_policy' => policy })
    DataImportJob.perform_now(data_import)
    data_import.reload
  end

  # Actualizar un contacto dispara la búsqueda de avatar en Gravatar, que no es
  # parte de lo que se prueba aquí y WebMock bloquea.
  before do
    allow_any_instance_of(Contact).to receive(:fetch_avatar_from_gravatar) # rubocop:disable RSpec/AnyInstance
  end

  let(:headers) { %w[name email phone_number] }

  describe 'prefijo a partir del país' do
    it 'antepone el prefijo del país a los números locales' do
      run_import([headers, ['Ana', 'ana@example.com', '3001234567']])

      expect(account.contacts.last.phone_number).to eq('+573001234567')
    end

    it 'no duplica el prefijo cuando el archivo ya lo trae' do
      run_import([headers, ['Ana', 'ana@example.com', '+573001234567']])

      expect(account.contacts.last.phone_number).to eq('+573001234567')
    end

    it 'usa el país elegido, no el que sugiere el número' do
      run_import([headers, ['Ana', 'ana@example.com', '3001234567']], country: 'AF')

      expect(account.contacts.last.phone_number).to eq('+933001234567')
    end
  end

  describe 'política skip (por defecto)' do
    it 'no crea un contacto repetido cuando el teléfono ya existe' do
      create(:contact, account: account, phone_number: '+573001234567', name: 'Original')

      expect { run_import([headers, ['Ana', 'ana@example.com', '3001234567']]) }
        .not_to change(Contact, :count)
    end

    it 'deja intacto el lead existente' do
      existing = create(:contact, account: account, phone_number: '+573001234567', name: 'Original')

      run_import([headers, ['Nombre nuevo', 'nuevo@example.com', '3001234567']])

      expect(existing.reload.name).to eq('Original')
      expect(existing.email).to be_nil
    end

    it 'detecta el duplicado también por correo' do
      create(:contact, account: account, email: 'ana@example.com')

      expect { run_import([headers, ['Ana', 'ANA@example.com', '']]) }
        .not_to change(Contact, :count)
    end
  end

  describe 'política update' do
    it 'sobrescribe el lead existente con los datos del archivo' do
      existing = create(:contact, account: account, phone_number: '+573001234567', name: 'Original')

      run_import([headers, ['Nombre nuevo', 'nuevo@example.com', '3001234567']], policy: 'update')

      expect(existing.reload.name).to eq('Nombre nuevo')
      expect(existing.email).to eq('nuevo@example.com')
    end

    it 'sigue sin crear un contacto extra' do
      create(:contact, account: account, phone_number: '+573001234567')

      expect { run_import([headers, ['Ana', 'ana@example.com', '3001234567']], policy: 'update') }
        .not_to change(Contact, :count)
    end
  end

  describe 'igualdad exacta' do
    it 'trata como leads distintos dos números que difieren en un dígito' do
      create(:contact, account: account, phone_number: '+573001234567')

      expect { run_import([headers, ['Otra', 'otra@example.com', '3001234568']]) }
        .to change(Contact, :count).by(1)
    end
  end

  describe 'duplicados dentro del propio archivo' do
    it 'monta una sola vez la fila repetida' do
      rows = [headers,
              ['Ana', 'ana@example.com', '3001234567'],
              ['Ana otra vez', 'otra@example.com', '+573001234567']]

      expect { run_import(rows) }.to change(Contact, :count).by(1)
    end
  end

  describe 'resumen' do
    it 'guarda los contadores de la importación en stats' do
      create(:contact, account: account, phone_number: '+573001234567')
      rows = [headers,
              ['Nueva', 'nueva@example.com', '3009999999'],
              ['Duplicada', 'dup@example.com', '3001234567'],
              ['Sin identidad', '', '']]

      stats = run_import(rows).stats['jabvox']

      expect(stats).to include('created' => 1, 'duplicates_skipped' => 1, 'invalid' => 1,
                               'country' => 'CO', 'duplicate_policy' => 'skip')
    end

    it 'cuenta los teléfonos que ya traían prefijo, para poder avisar al usuario' do
      stats = run_import([headers, ['Ana', 'ana@example.com', '+573001234567']]).stats['jabvox']

      expect(stats['phones_with_prefix']).to eq(1)
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'no considera duplicado un contacto de otra cuenta' do
      create(:contact, account: create(:account), phone_number: '+573001234567')

      expect { run_import([headers, ['Ana', 'ana@example.com', '3001234567']]) }
        .to change { account.contacts.count }.by(1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
