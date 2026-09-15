# frozen_string_literal: true

require 'rails_helper'

describe Jabvox::AffiliateLeadImporter do
  let(:account) { create(:account) }
  let(:affiliate) { create(:jabvox_affiliate, account: account) }

  subject(:importer) do
    described_class.new(account: account, affiliate: affiliate, country_iso: 'CO')
  end

  describe '#import_row' do
    it 'crea el lead y lo liga al afiliado, con el prefijo del país' do
      expect(importer.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })).to eq(:ok)

      contact = account.contacts.last
      expect(contact.phone_number).to eq('+573001234567')
      expect(account.jabvox_leads.last.jabvox_affiliate).to eq(affiliate)
      expect(importer.counters[:rows_ok]).to eq(1)
    end

    it 'NO crea duplicado cuando el teléfono ya existe: lo cuenta como duplicado' do
      create(:contact, account: account, phone_number: '+573001234567')

      expect { importer.import_row({ 'name' => 'Ana', 'phone' => '3001234567' }) }
        .not_to change(Contact, :count)
      expect(importer.counters[:rows_duplicated]).to eq(1)
    end

    it 'NO actualiza el lead existente — el afiliado nunca modifica datos ajenos' do
      existing = create(:contact, account: account, name: 'Nombre original',
                                  phone_number: '+573001234567')

      importer.import_row({ 'name' => 'Nombre nuevo', 'phone' => '3001234567' })

      expect(existing.reload.name).to eq('Nombre original')
    end

    it 'detecta el duplicado también por correo' do
      create(:contact, account: account, email: 'ana@example.com')

      importer.import_row({ 'name' => 'Ana', 'email' => 'ANA@example.com' })

      expect(importer.counters[:rows_duplicated]).to eq(1)
    end

    it 'trata como distinto un número que difiere en un dígito' do
      create(:contact, account: account, phone_number: '+573001234567')

      expect(importer.import_row({ 'name' => 'Otra', 'phone' => '3001234568' })).to eq(:ok)
    end

    it 'no monta dos veces la misma fila repetida dentro del archivo' do
      importer.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })
      importer.import_row({ 'name' => 'Ana', 'phone' => '+573001234567' })

      expect(importer.counters).to include(rows_ok: 1, rows_duplicated: 1)
    end

    it 'rechaza filas sin identidad utilizable en vez de montarlas' do
      expect(importer.import_row({ 'name' => 'Sin datos' })).to eq(:failed)
      expect(Contact.count).to eq(0)
    end

    it 'rechaza filas sin nombre' do
      expect(importer.import_row({ 'phone' => '3001234567' })).to eq(:failed)
    end

    it 'no ve contactos de otra cuenta al deduplicar' do
      create(:contact, account: create(:account), phone_number: '+573001234567')

      expect(importer.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })).to eq(:ok)
    end

    it 'usa el prefijo del país del importador, no el que sugiere el número' do
      afghan = described_class.new(account: account, affiliate: affiliate, country_iso: 'AF')
      afghan.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })

      expect(account.contacts.last.phone_number).to eq('+933001234567')
    end

    it 'acepta números que ya traen el prefijo sin duplicarlo' do
      importer.import_row({ 'name' => 'Ana', 'phone' => '+573001234567' })

      expect(account.contacts.last.phone_number).to eq('+573001234567')
    end
  end

  describe '#import_one' do
    it 'crea el lead y registra el alta manual' do
      result = importer.import_one(name: 'Ana', phone_raw: '3001234567', email_raw: nil)

      expect(result.outcome).to eq(:ok)
      import = JabvoxAffiliateImport.last
      expect(import).to have_attributes(import_type: 'manual', rows_ok: 1, rows_duplicated: 0)
    end

    it 'devuelve :duplicated sin crear nada cuando el lead ya existe' do
      create(:contact, account: account, phone_number: '+573001234567')

      result = importer.import_one(name: 'Ana', phone_raw: '3001234567', email_raw: nil)

      expect(result.outcome).to eq(:duplicated)
      expect(JabvoxAffiliateImport.last.rows_duplicated).to eq(1)
    end
  end

  describe 'campaña' do
    it 'liga el lead a la campaña de la cuenta cuando se indica' do
      campaign = JabvoxCampaign.create!(account: account, name_jabvox: 'Enero')
      with_campaign = described_class.new(account: account, affiliate: affiliate,
                                          country_iso: 'CO', campaign_name: 'Enero')

      with_campaign.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })

      expect(account.jabvox_leads.last.jabvox_campaign).to eq(campaign)
    end

    it 'ignora una campaña de otra cuenta' do
      JabvoxCampaign.create!(account: create(:account), name_jabvox: 'Ajena')
      with_campaign = described_class.new(account: account, affiliate: affiliate,
                                          country_iso: 'CO', campaign_name: 'Ajena')

      with_campaign.import_row({ 'name' => 'Ana', 'phone' => '3001234567' })

      expect(account.jabvox_leads.last.jabvox_campaign).to be_nil
    end
  end
end
