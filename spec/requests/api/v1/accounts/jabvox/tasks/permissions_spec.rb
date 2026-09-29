# frozen_string_literal: true

require 'rails_helper'

# Permisos del módulo de Tareas.
#
# Antes el gate salía antes de comprobar nada si el usuario no tenía rol personalizado, así
# que cualquier agente creaba tableros, editaba tareas y ejecutaba automatizaciones de
# envío. Ahora gestionar exige el permiso siempre, y borrar es exclusivo del administrador.
RSpec.describe 'Jabvox tasks permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: admin.id) }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Entrada', position_jabvox: 0)
  end
  let(:task) do
    account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id,
                                 title_jabvox: 'Pendiente', created_by_id: admin.id)
  end

  # Agente sin rol personalizado: ya no basta con ser miembro de la cuenta.
  let(:sin_rol) { create(:user, account: account, role: :agent) }

  # Agente con un rol que concede la gestión del módulo.
  let(:gestor) do
    user = create(:user, account: account, role: :agent)
    rol = account.custom_roles.create!(name: 'Gestor', permissions: ['jabvox_tasks_manage'])
    account.account_users.find_by(user: user).update!(custom_role: rol)
    user
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def url(path) = "/api/v1/accounts/#{account.id}/jabvox/tasks/#{path}"

  describe 'gestionar exige permiso' do
    it 'no deja crear un tablero a quien no tiene rol' do
      post url('boards'), params: { board: { name_jabvox: 'Nuevo' } },
                          headers: sin_rol.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'no deja crear una tarea a quien no tiene rol' do
      post url('tasks'), params: { task: { title_jabvox: 'X', board_id: board.id, stage_id: stage.id } },
                         headers: sin_rol.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'deja crear a quien tiene el permiso' do
      post url('tasks'), params: { task: { title_jabvox: 'X', board_id: board.id, stage_id: stage.id } },
                         headers: gestor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'deja crear al administrador' do
      post url('boards'), params: { board: { name_jabvox: 'Nuevo' } },
                          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    # Leer sigue abierto a los miembros de la cuenta: el gate es solo de escritura.
    it 'deja ver los tableros a quien no tiene rol' do
      get url('boards'), headers: sin_rol.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'borrar es solo del administrador' do
    it 'no deja a un gestor borrar una tarea' do
      delete url("tasks/#{task.id}"), headers: gestor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JabvoxTask.where(id: task.id)).to exist
    end

    it 'no deja a un gestor borrar una columna' do
      delete url("boards/#{board.id}/stages/#{stage.id}"),
             headers: gestor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'no deja a un gestor borrar un tablero' do
      delete url("boards/#{board.id}"), headers: gestor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JabvoxTaskBoard.where(id: board.id)).to exist
    end

    it 'deja al administrador borrar una tarea' do
      delete url("tasks/#{task.id}"), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end

    it 'deja al administrador borrar un tablero' do
      delete url("boards/#{board.id}"), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
    end
  end

  # El mensaje no distingue entre "no tienes rol", "tu rol no lo concede" y "esto es de
  # admins": decirlo convertiría el endpoint en un mapa de los permisos de la cuenta.
  describe 'el error no filtra el motivo' do
    it 'devuelve el mismo mensaje sin rol que con rol insuficiente' do
      post url('boards'), params: { board: { name_jabvox: 'A' } },
                          headers: sin_rol.create_new_auth_token, as: :json
      sin_rol_msg = response.parsed_body['error']

      delete url("tasks/#{task.id}"), headers: gestor.create_new_auth_token, as: :json

      expect(response.parsed_body['error']).to eq(sin_rol_msg)
      expect(sin_rol_msg).not_to match(/rol|administrador|jabvox_tasks_manage/i)
    end
  end
end
