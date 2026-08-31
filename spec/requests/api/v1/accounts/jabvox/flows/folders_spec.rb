# frozen_string_literal: true

require 'rails_helper'

# Carpetas de flujos: CRUD, mover flujos dentro y fuera, aislamiento entre
# cuentas y qué ocurre al borrar una carpeta que todavía tiene flujos.
RSpec.describe 'Jabvox flows folders API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  before { account.update!(jabvox_advanced_automations_enabled_jabvox: true) }

  def url(path = '') = "/api/v1/accounts/#{account.id}/jabvox/flows#{path}"

  describe 'gateo por módulo' do
    it 'responde 403 con el módulo apagado' do
      account.update!(jabvox_advanced_automations_enabled_jabvox: false)

      get url('/folders'), headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'CRUD' do
    it 'crea una carpeta' do
      post url('/folders'), params: { name: 'Ventas' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'Ventas', 'flowsCount' => 0)
    end

    it 'rechaza una carpeta sin nombre' do
      post url('/folders'), params: { name: '' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza dos carpetas con el mismo nombre en la cuenta' do
      post url('/folders'), params: { name: 'Ventas' }, headers: headers, as: :json
      post url('/folders'), params: { name: 'Ventas' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # El nombre solo es único DENTRO de la cuenta.
    it 'permite el mismo nombre en otra cuenta' do
      other = create(:account)
      JabvoxFlowFolder.create!(account: other, name: 'Ventas')

      post url('/folders'), params: { name: 'Ventas' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'renombra una carpeta' do
      folder = JabvoxFlowFolder.create!(account: account, name: 'Vieja')

      patch url("/folders/#{folder.id}"), params: { name: 'Nueva' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(folder.reload.name).to eq('Nueva')
    end

    it 'lista las carpetas por nombre con su número de flujos' do
      b = JabvoxFlowFolder.create!(account: account, name: 'B')
      JabvoxFlowFolder.create!(account: account, name: 'A')
      JabvoxFlow.create!(account: account, name: 'Uno', folder: b)

      get url('/folders'), headers: headers, as: :json

      expect(response.parsed_body.map { |f| f['name'] }).to eq(%w[A B])
      expect(response.parsed_body.find { |f| f['name'] == 'B' }['flowsCount']).to eq(1)
    end
  end

  describe 'aislamiento entre cuentas' do
    let(:other_account) { create(:account) }

    it 'no lista carpetas de otra cuenta' do
      JabvoxFlowFolder.create!(account: other_account, name: 'Ajena')

      get url('/folders'), headers: headers, as: :json

      expect(response.parsed_body).to be_empty
    end

    it 'no deja renombrar ni borrar una carpeta ajena' do
      foreign = JabvoxFlowFolder.create!(account: other_account, name: 'Ajena')

      patch url("/folders/#{foreign.id}"), params: { name: 'Robada' }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      delete url("/folders/#{foreign.id}"), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.name).to eq('Ajena')
    end

    # La clave foránea apunta a la tabla, no a la cuenta: sin la validación del
    # modelo este PATCH sacaría el flujo de su cuenta.
    it 'no deja mover un flujo a una carpeta de otra cuenta' do
      foreign = JabvoxFlowFolder.create!(account: other_account, name: 'Ajena')
      flow = JabvoxFlow.create!(account: account, name: 'Mío')

      patch url("/#{flow.id}"), params: { folderId: foreign.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flow.reload.folder_id).to be_nil
    end
  end

  describe 'mover flujos' do
    let(:folder) { JabvoxFlowFolder.create!(account: account, name: 'Ventas') }
    let(:flow) { JabvoxFlow.create!(account: account, name: 'Mi flujo') }

    it 'mete un flujo en una carpeta' do
      patch url("/#{flow.id}"), params: { folderId: folder.id }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(flow.reload.folder_id).to eq(folder.id)
    end

    it 'saca un flujo de la carpeta a la raíz' do
      flow.update!(folder: folder)

      patch url("/#{flow.id}"), params: { folderId: nil }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(flow.reload.folder_id).to be_nil
    end

    it 'filtra el listado de flujos por carpeta' do
      flow.update!(folder: folder)
      JabvoxFlow.create!(account: account, name: 'Suelto')

      get url, params: { folderId: folder.id }, headers: headers, as: :json

      expect(response.parsed_body.map { |f| f['name'] }).to eq(['Mi flujo'])
    end

    it 'crea un flujo directamente dentro de una carpeta' do
      post url, params: { name: 'Nuevo', folderId: folder.id }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JabvoxFlow.find(response.parsed_body['id']).folder_id).to eq(folder.id)
    end
  end

  # DECISIÓN: borrar la carpeta NUNCA borra flujos. Es el fallo seguro: perder
  # trabajo por borrar un contenedor no se puede deshacer, quedar suelto sí.
  describe 'borrado de una carpeta con flujos' do
    it 'deja los flujos sueltos en la raíz y dice cuántos movió' do
      folder = JabvoxFlowFolder.create!(account: account, name: 'Ventas')
      flow = JabvoxFlow.create!(account: account, name: 'Mi flujo', folder: folder)

      delete url("/folders/#{folder.id}"), headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('movedToRoot' => 1)
      expect(flow.reload.folder_id).to be_nil
      expect(JabvoxFlow.exists?(flow.id)).to be(true)
      expect(JabvoxFlowFolder.exists?(folder.id)).to be(false)
    end

    it 'borra una carpeta vacía sin más' do
      folder = JabvoxFlowFolder.create!(account: account, name: 'Vacía')

      delete url("/folders/#{folder.id}"), headers: headers, as: :json

      expect(response.parsed_body).to eq('movedToRoot' => 0)
    end

    # Un flujo ACTIVO no se borra sin desactivar; borrar su carpeta tampoco debe
    # tocarlo, solo sacarlo de ella.
    it 'no detiene ni borra un flujo activo al borrar su carpeta' do
      folder = JabvoxFlowFolder.create!(account: account, name: 'Ventas')
      flow = JabvoxFlow.create!(account: account, name: 'Activo', folder: folder, status: :active)

      delete url("/folders/#{folder.id}"), headers: headers, as: :json

      expect(flow.reload).to be_active
      expect(flow.folder_id).to be_nil
    end
  end
end
