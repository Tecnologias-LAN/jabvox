# frozen_string_literal: true

require 'rails_helper'

# Sedes del calendario: dónde se atiende, con su zona horaria y su horario comercial.
# Solo el administrador las gestiona, porque definen el horario que ve todo el equipo.
RSpec.describe 'Jabvox calendar branches', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.update!(jabvox_calendar_enabled_jabvox: true) }

  def url(path = nil) = ["/api/v1/accounts/#{account.id}/jabvox/branches", path].compact.join('/')

  def create_payload(**overrides)
    {
      branch: { name_jabvox: 'Consultorio Norte', timezone_jabvox: 'America/Bogota' },
      hours: [{ day_of_week: 1, open_minute: 360, close_minute: 720 }],
      **overrides
    }
  end

  describe 'quién puede gestionarlas' do
    it 'un agente no puede crearlas' do
      post url, params: create_payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(account.jabvox_branches).to be_empty
    end

    it 'el administrador sí' do
      post url, params: create_payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    # Leer está abierto: el calendario necesita las sedes para filtrar y sombrear horarios.
    it 'un agente sí puede listarlas' do
      account.jabvox_branches.create!(name_jabvox: 'Centro', timezone_jabvox: 'America/Bogota')

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['name_jabvox']).to eq('Centro')
    end

    it 'un agente no puede borrarlas' do
      branch = account.jabvox_branches.create!(name_jabvox: 'Centro',
                                               timezone_jabvox: 'America/Bogota')

      delete url(branch.id), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'horario comercial' do
    it 'guarda una jornada partida como dos franjas del mismo día' do
      post url, params: create_payload(hours: [
                                         { day_of_week: 1, open_minute: 360, close_minute: 720 },
                                         { day_of_week: 1, open_minute: 840, close_minute: 1080 }
                                       ]),
                headers: admin.create_new_auth_token, as: :json

      horas = response.parsed_body['hours']
      expect(horas.size).to eq(2)
      expect(horas.map { |h| h['open_minute'] }).to eq([360, 840])
    end

    # Antes se borraba el horario anterior y las franjas inválidas se descartaban en
    # silencio devolviendo 200: el admin perdía lo que tenía y creía haber guardado.
    it 'no pierde el horario anterior si el nuevo es inválido' do
      post url, params: create_payload, headers: admin.create_new_auth_token, as: :json
      branch_id = response.parsed_body['id']

      patch url(branch_id),
            params: { hours: [{ day_of_week: 1, open_minute: 720, close_minute: 360 }] },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      get url(branch_id), headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['hours'].size).to eq(1)
    end

    it 'rechaza una franja que cierra antes de abrir' do
      branch = account.jabvox_branches.create!(name_jabvox: 'Centro',
                                               timezone_jabvox: 'America/Bogota')
      hora = branch.hours.build(day_of_week: 1, open_minute: 720, close_minute: 360)

      expect(hora).not_to be_valid
    end
  end

  describe 'zona horaria' do
    it 'rechaza una zona inventada' do
      post url, params: create_payload(branch: { name_jabvox: 'X', timezone_jabvox: 'Marte/Olimpo' }),
                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'responsables' do
    it 'admite una sede sin responsable' do
      post url, params: create_payload(manager_ids: []),
                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['manager_ids']).to eq([])
    end

    it 'admite varios responsables' do
      post url, params: create_payload(manager_ids: [admin.id, agent.id]),
                headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['manager_ids']).to contain_exactly(admin.id, agent.id)
    end

    it 'descarta a un usuario de otra cuenta' do
      ajeno = create(:user, account: create(:account))

      post url, params: create_payload(manager_ids: [ajeno.id]),
                headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['manager_ids']).to eq([])
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'no encuentra la sede de otra cuenta' do
      ajena = create(:account).jabvox_branches.create!(name_jabvox: 'Ajena',
                                                       timezone_jabvox: 'UTC')

      get url(ajena.id), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
