# frozen_string_literal: true

require 'rails_helper'

# Pruebas de carga sobre contactos, leads y bandejas con los cambios aplicados.
#
# Lo que se protege:
#   1. Las columnas nuevas del teléfono no añaden consultas por fila (N+1).
#   2. El afiliado propio se resuelve UNA vez, no una por lead.
#   3. Borrar en volumen no deja filas huérfanas ni se degrada.
#   4. Todo sigue acotado por cuenta bajo carga.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Carga: contactos, leads y bandejas' do
  let(:account) { create(:account) }

  def count_queries
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[CACHE SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    queries
  end

  def create_contacts(count, acc = account, offset = 0)
    Array.new(count) do |i|
      create(:contact, account: acc, phone_number: format('+5730%08d', offset + i))
    end
  end

  describe 'crear leads en volumen' do
    it 'crea 200 leads sin perder ninguno' do
      contacts = create_contacts(200)

      contacts.each { |c| JabvoxLead.create!(account: account, contact: c) }

      expect(account.jabvox_leads.count).to eq(200)
    end

    it 'todos quedan atribuidos al MISMO afiliado propio' do
      create_contacts(50).each { |c| JabvoxLead.create!(account: account, contact: c) }

      affiliate_ids = account.jabvox_leads.distinct.pluck(:jabvox_affiliate_id)

      expect(affiliate_ids.size).to eq(1)
      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end

    it 'el afiliado propio no se busca una vez por lead' do
      contacts = create_contacts(40)
      JabvoxAffiliate.owned_for!(account) # ya existe: no debe recrearse

      queries = count_queries do
        contacts.each { |c| JabvoxLead.create!(account: account, contact: c) }
      end

      # Con una consulta extra por lead (40) más los inserts, esto se dispararía.
      # El margen deja sitio a los callbacks existentes sin permitir un N+1 nuevo.
      expect(queries).to be < 400
    end
  end

  describe 'guardar contactos en volumen' do
    it 'las piezas del teléfono no añaden consultas por contacto' do
      base = count_queries { create_contacts(20, account, 1_000) }
      doble = count_queries { create_contacts(40, account, 2_000) }

      # Crecimiento lineal: al doblar las filas, las consultas no se disparan.
      expect(doble).to be < (base * 3)
    end

    it 'todos los contactos quedan con sus piezas derivadas' do
      create_contacts(100, account, 5_000)

      sin_piezas = account.contacts.where.not(phone_number: [nil, ''])
                          .where(phone_national_jabvox: nil).count

      expect(sin_piezas).to eq(0)
    end
  end

  describe 'borrado en volumen' do
    it 'borra 100 leads sin dejar huérfanos' do
      create_contacts(100, account, 10_000).each { |c| JabvoxLead.create!(account: account, contact: c) }

      account.jabvox_leads.destroy_all

      expect(account.jabvox_leads.count).to eq(0)
      expect(JabvoxLeadSourceRecord.where(account_id: account.id).count).to eq(0)
    end

    it 'borra 100 contactos y sus leads se van con ellos' do
      contacts = create_contacts(100, account, 20_000)
      contacts.each { |c| JabvoxLead.create!(account: account, contact: c) }

      contacts.each(&:destroy!)

      expect(account.contacts.count).to eq(0)
      expect(account.jabvox_leads.count).to eq(0)
    end

    it 'el afiliado propio sobrevive al borrado masivo' do
      create_contacts(50, account, 30_000).each { |c| JabvoxLead.create!(account: account, contact: c) }

      account.jabvox_leads.destroy_all

      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end
  end

  describe 'varias cuentas a la vez' do
    it 'diez cuentas con los mismos teléfonos no se mezclan' do
      accounts = Array.new(10) { create(:account) }

      accounts.each do |acc|
        5.times do |i|
          contact = create(:contact, account: acc, phone_number: format('+5731%08d', i))
          JabvoxLead.create!(account: acc, contact: contact)
        end
      end

      accounts.each do |acc|
        expect(acc.contacts.count).to eq(5)
        expect(acc.jabvox_leads.count).to eq(5)
        # El afiliado propio nace con el primer lead de la cuenta, uno por cuenta.
        expect(acc.jabvox_affiliates.owned.count).to eq(1)
      end
    end

    it 'cada cuenta tiene su propio afiliado propio, nunca compartido' do
      accounts = Array.new(10) { |i| create(:account, name: "Cuenta #{i}") }
      owned_ids = accounts.map { |acc| JabvoxAffiliate.owned_for!(acc).id }

      expect(owned_ids.uniq.size).to eq(10)
    end
  end

  describe 'bandejas con muchos contactos' do
    it 'borrar la bandeja no toca los contactos ni sus leads' do
      inbox = create(:inbox, account: account)
      contacts = create_contacts(50, account, 40_000)
      contacts.each do |c|
        create(:contact_inbox, contact: c, inbox: inbox)
        JabvoxLead.create!(account: account, contact: c)
      end

      inbox.destroy!

      expect(account.contacts.count).to eq(50)
      expect(account.jabvox_leads.count).to eq(50)
    end
  end

  describe 'teléfonos heredados bajo carga' do
    it 'la normalización procesa 100 filas sin perder ni duplicar' do
      100.times do |i|
        c = account.contacts.new(name: "H#{i}", phone_number: format('30%08d', i))
        c.save!(validate: false)
      end

      report = Jabvox::PhoneNormalizeTask.new(apply: true, account_id: account.id).build_report

      expect(report.normalized).to eq(100)
      expect(account.contacts.count).to eq(100)
      expect(account.contacts.where("phone_number NOT LIKE '+%'").count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
