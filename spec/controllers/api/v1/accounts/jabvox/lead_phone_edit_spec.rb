# frozen_string_literal: true

require 'rails_helper'

# Editar un lead guarda el teléfono con su prefijo y no daña el resto de sus
# datos (campaña, asignado, campos personalizados).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Edición del teléfono de un lead', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+573001234567') }
  let!(:lead) { JabvoxLead.create!(account: account, contact: contact) }

  before { account.update!(jabvox_leads_enabled_jabvox: true) }

  def update_lead(params)
    patch "/api/v1/accounts/#{account.id}/jabvox/leads/#{lead.id}/update_details",
          headers: admin.create_new_auth_token, params: params
  end

  describe 'guardar el teléfono' do
    it 'guarda el número con su prefijo y deriva las piezas' do
      update_lead({ contact: { phone_number: '+573009999999' } })

      expect(response).to have_http_status(:success)
      expect(contact.reload.phone_number).to eq('+573009999999')
      expect(contact.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3009999999')
    end

    it 'acepta cambiar a un número de otro país' do
      update_lead({ contact: { phone_number: '+93700123456' } })

      expect(contact.reload.phone_country_code_jabvox).to eq('+93')
      expect(contact.phone_national_jabvox).to eq('700123456')
    end

    it 'rechaza un número sin prefijo internacional y conserva el anterior' do
      update_lead({ contact: { phone_number: '3001234567' } })

      expect(contact.reload.phone_number).to eq('+573001234567')
    end
  end

  describe 'no dañar lo existente' do
    it 'editar solo el correo conserva el teléfono' do
      update_lead({ contact: { email: 'ana@example.com' } })

      expect(contact.reload.phone_number).to eq('+573001234567')
      expect(contact.email).to eq('ana@example.com')
    end

    it 'editar el país del lead no toca el teléfono' do
      update_lead({ contact: { country: 'CO' } })

      expect(contact.reload.phone_number).to eq('+573001234567')
      expect(contact.additional_attributes['country']).to eq('CO')
    end

    it 'cambiar el teléfono no pierde la campaña del lead' do
      campaign = JabvoxCampaign.create!(account: account, name_jabvox: 'Enero')
      lead.update!(jabvox_campaign: campaign)

      update_lead({ contact: { phone_number: '+573009999999' } })

      expect(lead.reload.jabvox_campaign).to eq(campaign)
    end

    it 'cambiar el teléfono no pierde el afiliado que lo trajo' do
      affiliate = create(:jabvox_affiliate, account: account)
      lead.update!(jabvox_affiliate: affiliate)

      update_lead({ contact: { phone_number: '+573009999999' } })

      expect(lead.reload.jabvox_affiliate).to eq(affiliate)
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'no permite editar un lead de otra cuenta' do
      other = create(:account)
      other_contact = create(:contact, account: other, phone_number: '+573007777777')
      other_lead = JabvoxLead.create!(account: other, contact: other_contact)

      patch "/api/v1/accounts/#{account.id}/jabvox/leads/#{other_lead.id}/update_details",
            headers: admin.create_new_auth_token,
            params: { contact: { phone_number: '+573008888888' } }

      expect(response).not_to have_http_status(:success)
      expect(other_contact.reload.phone_number).to eq('+573007777777')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
