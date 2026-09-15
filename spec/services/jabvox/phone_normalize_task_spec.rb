# frozen_string_literal: true

require 'rails_helper'

describe Jabvox::PhoneNormalizeTask do
  let(:account) { create(:account) }

  def legacy_contact(phone, acc = account)
    contact = acc.contacts.new(name: "C#{phone}", phone_number: phone)
    contact.save!(validate: false)
    contact
  end

  describe 'modo simulación (por defecto)' do
    it 'informa lo que cambiaría SIN escribir nada' do
      contact = legacy_contact('573001234567')

      report = described_class.new(account_id: account.id).build_report

      expect(report.normalized).to eq(1)
      expect(contact.reload.phone_number).to eq('573001234567')
    end
  end

  describe 'modo aplicar' do
    it 'normaliza un número al que le falta el "+"' do
      contact = legacy_contact('573001234567')

      described_class.new(apply: true, account_id: account.id).build_report

      expect(contact.reload.phone_number).to eq('+573001234567')
    end

    it 'normaliza un número local añadiendo el país' do
      contact = legacy_contact('3001234567')

      described_class.new(apply: true, account_id: account.id).build_report

      expect(contact.reload.phone_number).to eq('+573001234567')
    end

    it 'rellena también las piezas del teléfono' do
      contact = legacy_contact('3001234567')

      described_class.new(apply: true, account_id: account.id).build_report

      expect(contact.reload.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end

    it 'NO toca los que ya están en E.164' do
      contact = legacy_contact('+573009999999')

      report = described_class.new(apply: true, account_id: account.id).build_report

      expect(report.scanned).to eq(0)
      expect(contact.reload.phone_number).to eq('+573009999999')
    end

    it 'usa el país indicado' do
      contact = legacy_contact('700123456')

      described_class.new(apply: true, account_id: account.id, country: 'AF').build_report

      expect(contact.reload.phone_number).to eq('+93700123456')
    end
  end

  describe 'seguridad: nunca pierde datos' do
    it 'SALTA la fila cuyo número normalizado ya pertenece a otro contacto' do
      create(:contact, account: account, phone_number: '+573001234567', name: 'El que ya estaba')
      duplicado = legacy_contact('3001234567')

      report = described_class.new(apply: true, account_id: account.id).build_report

      expect(report.conflicts).to eq(1)
      expect(report.normalized).to eq(0)
      # Ninguno de los dos se toca ni se borra: queda para revisión manual.
      expect(duplicado.reload.phone_number).to eq('3001234567')
      expect(Contact.where(account_id: account.id).count).to eq(2)
    end

    it 'no borra ni fusiona contactos en ningún caso' do
      legacy_contact('573001234567')
      legacy_contact('3009999999')

      expect { described_class.new(apply: true, account_id: account.id).build_report }
        .not_to change(Contact, :count)
    end

    it 'reporta como no normalizable lo que no tiene arreglo, sin tocarlo' do
      contact = legacy_contact('sin-digitos')

      report = described_class.new(apply: true, account_id: account.id).build_report

      expect(report.unparseable).to eq(1)
      expect(contact.reload.phone_number).to eq('sin-digitos')
    end
  end

  describe 'alcance' do
    it 'solo procesa la cuenta indicada' do
      otra = create(:account)
      ajeno = legacy_contact('573001234567', otra)

      described_class.new(apply: true, account_id: account.id).build_report

      expect(ajeno.reload.phone_number).to eq('573001234567')
    end

    it 'respeta el límite de filas' do
      3.times { |i| legacy_contact("30012345#{i}0") }

      report = described_class.new(apply: true, account_id: account.id, limit: 2).build_report

      expect(report.scanned).to eq(2)
    end
  end

  describe 'después de normalizar' do
    it 'el contacto queda deduplicable por los importadores' do
      legacy_contact('3001234567')
      described_class.new(apply: true, account_id: account.id).build_report

      index = Jabvox::LeadIdentityService.existing_index(account, phones: ['+573001234567'])

      expect(Jabvox::LeadIdentityService.match_existing(index, phone: '+573001234567')).to be_present
    end

    it 'el marcador sigue pudiendo llamar al número reparado' do
      contact = legacy_contact('3001234567')
      described_class.new(apply: true, account_id: account.id).build_report

      dialed = Jabvox::PhoneNormalizer.for_dialing(contact.reload.phone_number)

      expect(dialed).to eq('573001234567')
    end
  end
end
