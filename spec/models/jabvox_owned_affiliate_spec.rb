# frozen_string_literal: true

require 'rails_helper'

# El "afiliado propio" representa los leads que NO llegan por un afiliado
# externo. Vive en base de datos (una fila marcada con owned_jabvox), nunca
# hardcodeado, y no se puede modificar ni eliminar por ninguna vía.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Afiliado propio de la cuenta' do
  let(:account) { create(:account) }

  describe 'JabvoxAffiliate.owned_for!' do
    it 'crea el afiliado propio de la cuenta la primera vez' do
      affiliate = JabvoxAffiliate.owned_for!(account)

      expect(affiliate).to be_owned
      expect(affiliate.account).to eq(account)
    end

    it 'es idempotente: siempre devuelve el mismo' do
      first = JabvoxAffiliate.owned_for!(account)
      second = JabvoxAffiliate.owned_for!(account)

      expect(second.id).to eq(first.id)
      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end

    it 'cada cuenta tiene el suyo, nunca compartido' do
      other = create(:account)

      expect(JabvoxAffiliate.owned_for!(account).id)
        .not_to eq(JabvoxAffiliate.owned_for!(other).id)
    end

    it 'genera credenciales de portal como cualquier afiliado' do
      affiliate = JabvoxAffiliate.owned_for!(account)

      expect(affiliate.account_code).to be_present
      expect(affiliate.auth_token).to be_present
      expect(affiliate.portal_slug).to be_present
    end
  end

  describe 'inmutabilidad' do
    let(:owned) { JabvoxAffiliate.owned_for!(account) }

    it 'no se puede renombrar' do
      expect(owned.update(name: 'Otro nombre')).to be(false)
      expect(owned.reload.name).to eq(JabvoxAffiliate::DEFAULT_OWNED_NAME)
    end

    it 'no se puede desactivar' do
      expect(owned.update(active: false)).to be(false)
      expect(owned.reload.active).to be(true)
    end

    it 'no se puede dejar de ser propio' do
      expect(owned.update(owned_jabvox: false)).to be(false)
      expect(owned.reload).to be_owned
    end

    it 'no se puede mover a otra cuenta' do
      expect(owned.update(account: create(:account))).to be(false)
    end

    it 'no se puede eliminar' do
      owned # se crea antes de contar
      expect { owned.destroy }.not_to change(JabvoxAffiliate, :count)
      expect(JabvoxAffiliate.exists?(owned.id)).to be(true)
    end

    it 'SÍ permite regenerar sus credenciales (revocar un token filtrado)' do
      original = owned.auth_token
      owned.regenerate_auth_token!

      expect(owned.reload.auth_token).not_to eq(original)
    end

    it 'no se puede crear un segundo afiliado propio en la misma cuenta' do
      owned # el primero
      duplicate = JabvoxAffiliate.new(account: account, name: 'Falso propio', owned_jabvox: true)

      expect(duplicate.save).to be(false)
      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end
  end

  describe 'atribución automática de leads' do
    it 'un lead sin afiliado externo queda atribuido al propio' do
      contact = create(:contact, account: account)
      lead = JabvoxLead.create!(account: account, contact: contact)

      expect(lead.jabvox_affiliate).to be_owned
    end

    it 'un lead que llega por un afiliado externo conserva ese afiliado' do
      external = create(:jabvox_affiliate, account: account)
      contact = create(:contact, account: account)

      lead = JabvoxLead.create!(account: account, contact: contact, jabvox_affiliate: external)

      expect(lead.jabvox_affiliate).to eq(external)
      expect(lead.jabvox_affiliate).not_to be_owned
    end

    it 'los leads de una importación por CSV quedan en el afiliado propio' do
      contact = create(:contact, account: account, phone_number: '+573001234567')
      lead = account.jabvox_leads.create!(contact: contact)

      expect(lead.jabvox_affiliate.owned?).to be(true)
    end

    it 'el afiliado propio de una cuenta nunca recibe leads de otra' do
      other = create(:account)
      JabvoxLead.create!(account: account, contact: create(:contact, account: account))

      expect(JabvoxAffiliate.owned_for!(other).jabvox_leads).to be_empty
    end
  end

  describe 'scopes' do
    it 'separa el propio de los externos' do
      owned = JabvoxAffiliate.owned_for!(account)
      external = create(:jabvox_affiliate, account: account)

      expect(account.jabvox_affiliates.owned).to contain_exactly(owned)
      expect(account.jabvox_affiliates.external).to contain_exactly(external)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
