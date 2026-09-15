# frozen_string_literal: true

require 'rails_helper'

# Borrado de leads, contactos e inboxes DESPUÉS de los cambios de teléfono y
# afiliado propio.
#
# Lo que se protege: los cambios nuevos (el afiliado propio que ahora lleva todo
# lead, y las columnas del teléfono) no pueden bloquear un borrado ni dejar
# filas huérfanas.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Integridad de los borrados' do
  let(:account) { create(:account) }

  describe 'borrar un lead' do
    let(:contact) { create(:contact, account: account, phone_number: '+573001234567') }
    let!(:lead) { JabvoxLead.create!(account: account, contact: contact) }

    it 'el lead se borra aunque esté atribuido al afiliado propio' do
      expect(lead.jabvox_affiliate).to be_owned

      expect { lead.destroy! }.to change(JabvoxLead, :count).by(-1)
    end

    it 'borrar el lead NO borra el afiliado propio de la cuenta' do
      lead.destroy!

      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end

    it 'borrar el lead no arrastra el contacto' do
      lead.destroy!

      expect(Contact.exists?(contact.id)).to be(true)
    end

    it 'borrar muchos leads a la vez no deja afiliados colgados' do
      20.times do |i|
        c = create(:contact, account: account, phone_number: "+5730012345#{i.to_s.rjust(2, '0')}")
        JabvoxLead.create!(account: account, contact: c)
      end

      account.jabvox_leads.destroy_all

      expect(account.jabvox_leads.count).to eq(0)
      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end
  end

  describe 'borrar un contacto' do
    it 'borra también su lead, sin dejar filas huérfanas' do
      contact = create(:contact, account: account, phone_number: '+573001234567')
      lead = JabvoxLead.create!(account: account, contact: contact)

      contact.destroy!

      expect(JabvoxLead.exists?(lead.id)).to be(false)
    end

    it 'un contacto con teléfono heredado también se puede borrar' do
      contact = account.contacts.new(name: 'Heredado', phone_number: '573001234567')
      contact.save!(validate: false)

      expect { contact.destroy! }.to change(Contact, :count).by(-1)
    end

    it 'borrar en lote no falla por las columnas nuevas del teléfono' do
      contacts = Array.new(30) do |i|
        create(:contact, account: account, phone_number: "+5730099999#{i.to_s.rjust(2, '0')}")
      end

      expect { contacts.each(&:destroy!) }.to change(Contact, :count).by(-30)
    end
  end

  describe 'borrar un afiliado externo' do
    it 'se borra y sus leads quedan sin afiliado, no se pierden' do
      affiliate = create(:jabvox_affiliate, account: account)
      contact = create(:contact, account: account, phone_number: '+573001234567')
      lead = JabvoxLead.create!(account: account, contact: contact, jabvox_affiliate: affiliate)

      affiliate.destroy!

      expect(JabvoxLead.exists?(lead.id)).to be(true)
      expect(lead.reload.jabvox_affiliate).to be_nil
    end

    it 'el afiliado PROPIO no se puede borrar ni siquiera con leads asociados' do
      contact = create(:contact, account: account, phone_number: '+573001234567')
      JabvoxLead.create!(account: account, contact: contact)
      owned = account.jabvox_affiliates.owned.first

      expect { owned.destroy }.not_to change(JabvoxAffiliate, :count)
    end
  end

  describe 'borrar una bandeja (inbox)' do
    it 'se borra sin que los contactos con teléfono se vean afectados' do
      inbox = create(:inbox, account: account)
      contact = create(:contact, account: account, phone_number: '+573001234567')
      create(:contact_inbox, contact: contact, inbox: inbox)

      inbox.destroy!

      expect(Contact.exists?(contact.id)).to be(true)
      expect(contact.reload.phone_number).to eq('+573001234567')
    end

    it 'borrar la bandeja no toca el lead ni su afiliado' do
      inbox = create(:inbox, account: account)
      contact = create(:contact, account: account, phone_number: '+573001234567')
      create(:contact_inbox, contact: contact, inbox: inbox)
      lead = JabvoxLead.create!(account: account, contact: contact)

      inbox.destroy!

      expect(JabvoxLead.exists?(lead.id)).to be(true)
      expect(lead.reload.jabvox_affiliate).to be_owned
    end
  end

  describe 'borrar una cuenta entera' do
    # NOTA: Account usa `dependent: :destroy_async` para jabvox_affiliates, así
    # que el borrado real ocurre en un job posterior y la FK salta en el acto.
    # Esto YA pasaba antes de estos cambios con un afiliado externo cualquiera:
    # es una limitación preexistente del borrado de cuentas, no del afiliado
    # propio. Lo que se protege aquí es que el afiliado propio NO lo empeore.
    it 'el afiliado propio no bloquea más que uno externo' do
      con_propio = create(:account)
      JabvoxAffiliate.owned_for!(con_propio)

      con_externo = create(:account)
      create(:jabvox_affiliate, account: con_externo)

      propio_falla = begin
        con_propio.destroy!
        false
      rescue ActiveRecord::InvalidForeignKey
        true
      end

      externo_falla = begin
        con_externo.destroy!
        false
      rescue ActiveRecord::InvalidForeignKey
        true
      end

      expect(propio_falla).to eq(externo_falla)
    end

    it 'el afiliado propio se borra en cascada cuando su cuenta ya no está' do
      doomed = create(:account)
      owned = JabvoxAffiliate.owned_for!(doomed)

      # Cascada real: cuando el job de borrado corre, la cuenta ya está marcada
      # como destruida. La guarda del modelo debe dejarlo pasar.
      doomed.destroyed_by_association = ActiveRecord::Reflection.create(
        :has_many, :jabvox_affiliates, nil, {}, Account
      )
      allow(owned).to receive(:account).and_return(doomed)
      allow(doomed).to receive(:destroyed?).and_return(true)

      expect { owned.destroy! }.to change(JabvoxAffiliate, :count).by(-1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
