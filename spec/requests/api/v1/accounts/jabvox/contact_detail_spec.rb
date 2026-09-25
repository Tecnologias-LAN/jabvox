# frozen_string_literal: true

require 'rails_helper'

# Detalle unificado del contacto. Sustituye al spec del detalle de lead, que apuntaba a un
# modelo y una ruta que ya no existen.
#
# El foco está en `update_custom_fields`: cada valor tiene que pasar por el `coerce` de SU
# columna. Antes se guardaba todo como texto crudo, así que una fecha entraba como la cadena
# que escribiera el usuario y un select admitía cualquier cosa.
RSpec.describe 'Jabvox contact detail', type: :request do
  let(:account) { create(:account) }
  let!(:table) do
    account.jabvox_custom_tables.create!(name_jabvox: 'Contactos', kind_jabvox: 'single',
                                         linked_to_jabvox: 'contacts')
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Estrada') }

  # El controlador no declara flag propio, así que cae en el de por defecto del base
  # (`jabvox_kanban`), que se resuelve contra una columna, no contra enabled_features.
  before { account.update!(jabvox_kanban_enabled_jabvox: true) }

  def column(name, type, options = nil)
    table.jabvox_custom_columns.create!(name_jabvox: name, label_jabvox: name.capitalize,
                                        column_type_jabvox: type, options_jabvox: options)
  end

  def detail_url(id) = "/api/v1/accounts/#{account.id}/jabvox/contact_detail/#{id}"
  def update_url(id) = "#{detail_url(id)}/update_custom_fields"

  def patch_fields(fields)
    patch update_url(contact.id), params: { custom_fields: fields },
                                  headers: admin.create_new_auth_token, as: :json
  end

  def stored = contact.reload.custom_fields_jabvox

  describe 'GET show' do
    it 'sirve las definiciones con su tipo, para que el frontend pinte el control correcto' do
      column('fecha_cierre', 'date')

      get detail_url(contact.id), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      defs = response.parsed_body['custom_field_defs']
      expect(defs.first).to include('key' => 'fecha_cierre', 'column_type' => 'date')
    end
  end

  describe 'PATCH update_custom_fields' do
    it 'guarda una fecha normalizada a ISO' do
      column('fecha_cierre', 'date')

      patch_fields(fecha_cierre: '2026-09-24')

      expect(response).to have_http_status(:success)
      expect(stored['fecha_cierre']).to eq('2026-09-24')
    end

    it 'rechaza una fecha inválida en vez de guardarla como texto' do
      column('fecha_cierre', 'date')

      patch_fields(fecha_cierre: 'mañana')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(stored['fecha_cierre']).to be_nil
    end

    it 'guarda números como números, no como cadenas' do
      column('cupo', 'integer')
      column('tasa', 'float')

      patch_fields(cupo: '42', tasa: '3.5')

      expect(stored['cupo']).to eq(42)
      expect(stored['tasa']).to eq(3.5)
    end

    it 'guarda un booleano como true/false, no como la cadena "true"' do
      column('vip', 'boolean')

      patch_fields(vip: 'true')

      expect(stored['vip']).to be(true)
    end

    it 'acepta una opción configurada de un select y rechaza el resto' do
      column('origen', 'select', %w[web tienda])

      patch_fields(origen: 'web')
      expect(stored['origen']).to eq('web')

      patch_fields(origen: 'inventado')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(stored['origen']).to eq('web')
    end

    it 'guarda un multiselect como lista' do
      column('canales', 'multiselect', %w[sms email whatsapp])

      patch_fields(canales: %w[sms whatsapp])

      expect(stored['canales']).to eq(%w[sms whatsapp])
    end

    it 'descarta claves que no son campo personalizado de la cuenta' do
      column('origen', 'select', %w[web])

      patch_fields(origen: 'web', inyectada: 'valor')

      expect(stored).to have_key('origen')
      expect(stored).not_to have_key('inyectada')
    end

    it 'conserva los campos que no vienen en la petición' do
      column('origen', 'select', %w[web])
      column('vip', 'boolean')

      patch_fields(origen: 'web')
      patch_fields(vip: 'true')

      expect(stored['origen']).to eq('web')
      expect(stored['vip']).to be(true)
    end
  end
end
