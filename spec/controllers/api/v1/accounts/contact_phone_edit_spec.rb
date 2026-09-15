# frozen_string_literal: true

require 'rails_helper'

# Editar un contacto no debe dañar lo que ya estaba guardado.
#
# Lo que se protege aquí: guardar cambiando solo el nombre (o cualquier otro
# campo) NUNCA puede borrar ni alterar el teléfono, y las piezas derivadas se
# mantienen coherentes con el E.164.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Edición del teléfono de un contacto', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+573001234567') }

  def update_contact(params)
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: admin.create_new_auth_token, params: params
  end

  describe 'no dañar lo existente' do
    it 'editar solo el nombre conserva el teléfono' do
      update_contact({ name: 'Ana María' })

      expect(response).to have_http_status(:success)
      expect(contact.reload.phone_number).to eq('+573001234567')
      expect(contact.name).to eq('Ana María')
    end

    it 'editar solo el nombre conserva las piezas del teléfono' do
      update_contact({ name: 'Ana María' })

      expect(contact.reload.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end

    it 'editar el correo no toca el teléfono' do
      update_contact({ email: 'ana@example.com' })

      expect(contact.reload.phone_number).to eq('+573001234567')
    end
  end

  describe 'cambiar el teléfono' do
    it 'guarda el nuevo número y recalcula las piezas' do
      update_contact({ phone_number: '+573009999999' })

      expect(response).to have_http_status(:success)
      expect(contact.reload.phone_number).to eq('+573009999999')
      expect(contact.phone_national_jabvox).to eq('3009999999')
    end

    it 'cambiar a otro país actualiza el prefijo guardado' do
      update_contact({ phone_number: '+93700123456' })

      expect(contact.reload.phone_country_code_jabvox).to eq('+93')
      expect(contact.phone_national_jabvox).to eq('700123456')
    end

    it 'permite borrar el teléfono a propósito' do
      update_contact({ phone_number: '' })

      expect(contact.reload.phone_number).to be_blank
      expect(contact.phone_national_jabvox).to be_nil
    end

    it 'rechaza un teléfono sin prefijo internacional' do
      update_contact({ phone_number: '3001234567' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(contact.reload.phone_number).to eq('+573001234567')
    end
  end

  describe 'la API devuelve las piezas para el formulario' do
    it 'expone país y número local junto al E.164' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: admin.create_new_auth_token

      payload = response.parsed_body['payload']
      expect(payload['phone_number']).to eq('+573001234567')
      expect(payload['phone_country_code']).to eq('+57')
      expect(payload['phone_national']).to eq('3001234567')
    end
  end

  describe 'contactos que ya existían antes de este cambio' do
    it 'un contacto sin teléfono sigue funcionando' do
      sin_telefono = create(:contact, account: account, name: 'Sin teléfono')

      patch "/api/v1/accounts/#{account.id}/contacts/#{sin_telefono.id}",
            headers: admin.create_new_auth_token, params: { name: 'Otro nombre' }

      expect(response).to have_http_status(:success)
      expect(sin_telefono.reload.name).to eq('Otro nombre')
    end

    it 'un teléfono ya guardado obtiene sus piezas al volver a guardarlo' do
      # Simula una fila anterior a la migración: E.164 sin piezas derivadas.
      contact.update_columns(phone_country_code_jabvox: nil, phone_national_jabvox: nil) # rubocop:disable Rails/SkipsModelValidations

      update_contact({ phone_number: '+573001234568' })

      expect(contact.reload.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234568')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
