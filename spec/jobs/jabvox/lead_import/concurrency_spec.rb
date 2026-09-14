# frozen_string_literal: true

require 'rails_helper'

# Pruebas de carga y concurrencia de las importaciones.
#
# Lo que se protege aquí:
#   1. Varias cuentas importando a la vez no se mezclan ni se bloquean entre sí.
#   2. Un archivo grande no degrada a O(n²) consultas ni carga todo en memoria.
#   3. Dos subidas simultáneas del mismo afiliado no generan leads duplicados.
#   4. Nada de esto cae en las colas del worker principal.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Importaciones: concurrencia y carga' do
  # Tamaño de archivo usado en las pruebas de carga. Suficiente para que un
  # comportamiento cuadrático se note, sin volver lenta la suite.
  LOAD_ROWS = 300

  def rows_for(prefix, count)
    (1..count).map do |i|
      { 'name' => "#{prefix} #{i}", 'phone' => format('30%08d', i), 'email' => "#{prefix}#{i}@example.com" }
    end
  end

  describe 'varias cuentas importando a la vez' do
    it 'cada cuenta recibe solo sus propios leads' do
      accounts = Array.new(3) { create(:account) }
      affiliates = accounts.map { |a| create(:jabvox_affiliate, account: a) }

      # Los tres archivos traen EXACTAMENTE los mismos teléfonos: si la
      # deduplicación se saliera del scope de cuenta, dos de las tres cuentas
      # se quedarían sin leads.
      importers = accounts.each_with_index.map do |account, idx|
        Jabvox::AffiliateLeadImporter.new(account: account, affiliate: affiliates[idx], country_iso: 'CO')
      end
      rows = rows_for('Lead', 20)
      importers.each { |imp| rows.each { |row| imp.import_row(row) } }

      accounts.each do |account|
        expect(account.contacts.count).to eq(20)
        expect(account.jabvox_leads.count).to eq(20)
      end
      importers.each { |imp| expect(imp.counters[:rows_ok]).to eq(20) }
    end

    it 'un afiliado nunca ve ni pisa los leads de otra cuenta' do
      account_a = create(:account)
      account_b = create(:account)
      create(:contact, account: account_b, phone_number: '+573000000001', name: 'De la cuenta B')

      importer = Jabvox::AffiliateLeadImporter.new(
        account: account_a, affiliate: create(:jabvox_affiliate, account: account_a), country_iso: 'CO'
      )
      importer.import_row({ 'name' => 'De la cuenta A', 'phone' => '3000000001' })

      expect(account_a.contacts.count).to eq(1)
      expect(account_b.contacts.find_by(phone_number: '+573000000001').name).to eq('De la cuenta B')
    end
  end

  describe 'archivo grande' do
    let(:account) { create(:account) }
    let(:affiliate) { create(:jabvox_affiliate, account: account) }
    let(:importer) do
      Jabvox::AffiliateLeadImporter.new(account: account, affiliate: affiliate, country_iso: 'CO')
    end

    it "monta #{LOAD_ROWS} filas sin perder ninguna ni duplicar" do
      rows_for('Carga', LOAD_ROWS).each { |row| importer.import_row(row) }

      expect(importer.counters[:rows_ok]).to eq(LOAD_ROWS)
      expect(account.contacts.count).to eq(LOAD_ROWS)
      # Teléfonos únicos: ninguna fila se montó dos veces.
      expect(account.contacts.distinct.count(:phone_number)).to eq(LOAD_ROWS)
    end

    it 'hace un número de consultas proporcional a las filas, no cuadrático' do
      # Se mide con dos tamaños: si fuese cuadrático, al doblar las filas las
      # consultas se cuadruplicarían.
      small = count_queries { import_n(50) }
      large = count_queries { import_n(100) }

      expect(large).to be < (small * 3)
    end

    def import_n(count)
      acc = create(:account)
      imp = Jabvox::AffiliateLeadImporter.new(
        account: acc, affiliate: create(:jabvox_affiliate, account: acc), country_iso: 'CO'
      )
      rows_for("N#{count}", count).each { |row| imp.import_row(row) }
    end

    def count_queries
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[CACHE SCHEMA]) }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
      queries
    end
  end

  describe 'vista previa con muchas filas' do
    let(:account) { create(:account) }

    it 'resuelve los duplicados en pocas consultas, no una por fila' do
      # 200 contactos ya existentes; el archivo trae esos mismos 200.
      existing = (1..200).map { |i| format('+5730%08d', i) }
      existing.each { |phone| create(:contact, account: account, phone_number: phone) }
      rows = (1..200).map { |i| { 'name' => "L#{i}", 'phone_number' => format('30%08d', i) } }

      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[CACHE SCHEMA]) }
      result = nil
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        result = Jabvox::LeadImportPreviewService.new(account, rows, country_iso: 'CO').call
      end

      expect(result[:counts][:duplicadas_bd]).to eq(200)
      # Consultas agrupadas por lotes: muy lejos de las 200+ de un N+1.
      expect(queries).to be < 20
    end

    it 'acota el detalle devuelto aunque el archivo sea enorme' do
      rows = (1..1_000).map { |i| { 'name' => "L#{i}", 'phone_number' => format('31%08d', i) } }

      result = Jabvox::LeadImportPreviewService.new(account, rows, country_iso: 'CO').call

      expect(result[:counts][:nuevas]).to eq(1_000)
      expect(result[:rows].size).to eq(Jabvox::LeadImportPreviewService::MAX_DETAIL)
    end
  end

  describe 'subidas simultáneas del mismo afiliado' do
    let(:account) { create(:account) }
    let(:affiliate) { create(:jabvox_affiliate, account: account) }

    it 'no crea leads duplicados aunque dos importadores procesen la misma fila' do
      # Dos importadores distintos (como dos procesos del worker) con la misma
      # fila: el segundo debe verla ya existente en base, no crearla de nuevo.
      row = { 'name' => 'Ana', 'phone' => '3001234567' }
      first = Jabvox::AffiliateLeadImporter.new(account: account, affiliate: affiliate, country_iso: 'CO')
      second = Jabvox::AffiliateLeadImporter.new(account: account, affiliate: affiliate, country_iso: 'CO')

      expect(first.import_row(row)).to eq(:ok)
      expect(second.import_row(row)).to eq(:duplicated)
      expect(account.contacts.count).to eq(1)
    end

    it 'cuenta como duplicado, no como fallo, si pierde la carrera en el insert' do
      # El contacto lo creó otro proceso entre la comprobación y el insert: la
      # base rechaza por unicidad y eso es un duplicado, no un error del archivo.
      importer = Jabvox::AffiliateLeadImporter.new(account: account, affiliate: affiliate, country_iso: 'CO')
      allow_any_instance_of(Contact).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

      expect(importer.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })).to eq(:duplicated)
      expect(importer.counters[:rows_failed]).to eq(0)
      expect(importer.counters[:rows_duplicated]).to eq(1)
    end
  end

  describe 'aislamiento de colas' do
    it 'ninguna importación cae en las colas del worker principal' do
      main_queues = %w[critical high medium default low mailers]

      expect(main_queues).not_to include(DataImportJob.new.queue_name)
      expect(main_queues).not_to include(Jabvox::LeadImport::AffiliateCsvJob.new.queue_name)
      expect(main_queues).not_to include(Jabvox::LeadImport::SyncJob.new.queue_name)
    end

    it 'las importaciones que el usuario mira van en la cola prioritaria' do
      expect(DataImportJob.new.queue_name).to eq('jabvox_lead_import_interactive')
      expect(Jabvox::LeadImport::AffiliateCsvJob.new.queue_name).to eq('jabvox_lead_import_interactive')
      # El sync de BD externa puede durar horas: va en la cola de fondo.
      expect(Jabvox::LeadImport::SyncJob.new.queue_name).to eq('jabvox_lead_import')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
