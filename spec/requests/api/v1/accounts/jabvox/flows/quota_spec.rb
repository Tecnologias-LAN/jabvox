# frozen_string_literal: true

require 'rails_helper'

# Tope de flujos por cuenta: de dónde sale el límite, que se aplique en el
# servidor al crear y que no se pueda saltar con peticiones concurrentes.
RSpec.describe 'Jabvox flows quota', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  before { account.update!(jabvox_advanced_automations_enabled_jabvox: true) }

  def url(path = '') = "/api/v1/accounts/#{account.id}/jabvox/flows#{path}"

  def account_limit!(value)
    config = account.account_automation_config || account.build_account_automation_config
    config.update!(max_flows: value)
  end

  describe 'GET /quota' do
    it 'informa de ilimitado cuando no hay tope propio ni de plan' do
      get url('/quota'), headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('used' => 0, 'limit' => nil, 'unlimited' => true)
    end

    it 'refleja el tope del super admin y lo consumido' do
      account_limit!(3)
      JabvoxFlow.create!(account: account, name: 'Uno')

      get url('/quota'), headers: headers, as: :json

      expect(response.parsed_body).to include('used' => 1, 'limit' => 3, 'remaining' => 2,
                                              'unlimited' => false)
    end

    # Manda el MENOR de los dos: el plan no puede ampliar el tope que puso el
    # super admin, ni al revés.
    it 'usa el menor entre el tope de la cuenta y el del plan' do
      account_limit!(9)
      account.update!(limits: { 'advanced_flows' => 2 })

      get url('/quota'), headers: headers, as: :json

      expect(response.parsed_body['limit']).to eq(2)
    end

    it 'toma el límite del plan cuando la cuenta no tiene tope propio' do
      account.update!(limits: { 'advanced_flows' => 4 })

      get url('/quota'), headers: headers, as: :json

      expect(response.parsed_body['limit']).to eq(4)
    end
  end

  describe 'creación con el tope alcanzado' do
    before { account_limit!(2) }

    it 'crea hasta el tope y rechaza el siguiente con 422 y el conteo real' do
      2.times { |i| post url, params: { name: "Flujo #{i}" }, headers: headers, as: :json }
      expect(account.jabvox_flows.count).to eq(2)

      post url, params: { name: 'De más' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('2 de 2')
      expect(response.parsed_body['quota']).to include('used' => 2, 'limit' => 2, 'remaining' => 0)
      expect(account.jabvox_flows.count).to eq(2)
    end

    it 'aplica el tope también al duplicar' do
      post url, params: { name: 'Original' }, headers: headers, as: :json
      first_id = response.parsed_body['id']
      post url, params: { name: 'Segundo' }, headers: headers, as: :json

      post url("/#{first_id}/duplicate"), headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.jabvox_flows.count).to eq(2)
    end

    it 'vuelve a permitir crear tras borrar uno' do
      2.times { |i| post url, params: { name: "Flujo #{i}" }, headers: headers, as: :json }
      account.jabvox_flows.first.destroy!

      post url, params: { name: 'Hueco libre' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  # La garantía que se probó en la versión NestJS: con el tope en 5, N intentos
  # simultáneos dejan exactamente 5 flujos.
  #
  # Se usan hilos con conexión propia y una barrera: sin ella el pool (5
  # conexiones) los serializa y cada hilo ya ve lo insertado por el anterior, con
  # lo que la prueba pasaría incluso sin el lock. La barrera obliga a que todos
  # entren en la ventana contar+insertar a la vez, que es la carrera real.
  describe 'concurrencia' do
    # Sin fixtures transaccionales: los hilos necesitan ver los INSERT de los
    # demás, y una transacción de test envolvente los aislaría entre sí.
    self.use_transactional_tests = false

    let!(:concurrent_account) { create(:account, limits: { 'advanced_flows' => 5 }) }

    after do
      JabvoxFlow.where(account_id: concurrent_account.id).delete_all
      concurrent_account.destroy
    end

    it 'no deja pasar más del tope con 12 creaciones simultáneas' do
      account_id = concurrent_account.id
      threads_count = 12
      gate = Concurrent::CountDownLatch.new(threads_count)
      created = Concurrent::AtomicFixnum.new(0)
      rejected = Concurrent::AtomicFixnum.new(0)

      threads = Array.new(threads_count) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            service = Jabvox::Flows::QuotaService.new(Account.find(account_id))
            # Todos los hilos esperan aquí y arrancan la comprobación a la vez.
            gate.count_down
            gate.wait(5)
            service.create! do
              JabvoxFlow.create!(account_id: account_id, name: "Concurrente #{i}")
            end
            created.increment
          rescue Jabvox::Flows::QuotaService::QuotaExceeded
            rejected.increment
          end
        end
      end
      threads.each { |t| t.join(30) }

      expect(JabvoxFlow.where(account_id: account_id).count).to eq(5)
      expect(created.value).to eq(5)
      expect(rejected.value).to eq(threads_count - 5)
    end
  end
end
