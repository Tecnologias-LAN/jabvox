# frozen_string_literal: true

require 'rails_helper'

# Aislamiento entre cuentas del módulo de Tareas.
#
# board_id, stage_id y contact_id viajan en el formulario, así que sin validarlos se podía
# crear una tarea apuntando al tablero de OTRA cuenta: aterrizaba en su columna, disparaba
# sus automatizaciones y devolvía el nombre de su contacto en la respuesta.
RSpec.describe 'Jabvox tasks account isolation', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Propio', created_by_id: admin.id) }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 0)
  end

  let(:other_account) { create(:account) }
  let(:other_board) { other_account.jabvox_task_boards.create!(name_jabvox: 'Ajeno') }
  let(:other_stage) do
    other_board.stages.create!(account_id: other_account.id, name_jabvox: 'Ajena', position_jabvox: 0)
  end
  let(:other_contact) { create(:contact, account: other_account, name: 'Confidencial') }

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def tasks_url = "/api/v1/accounts/#{account.id}/jabvox/tasks/tasks"

  def crear(payload)
    post tasks_url, params: { task: payload }, headers: admin.create_new_auth_token, as: :json
  end

  describe 'al crear' do
    it 'rechaza un tablero de otra cuenta' do
      crear(title_jabvox: 'Intrusa', board_id: other_board.id, stage_id: other_stage.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JabvoxTask.where(title_jabvox: 'Intrusa')).to be_empty
    end

    it 'rechaza una columna de otra cuenta' do
      crear(title_jabvox: 'Intrusa', board_id: board.id, stage_id: other_stage.id)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Sin esto la respuesta devolvía el nombre del contacto ajeno en `lead_name`.
    it 'rechaza un contacto de otra cuenta y no filtra su nombre' do
      crear(title_jabvox: 'Intrusa', board_id: board.id, stage_id: stage.id,
            contact_id: other_contact.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include('Confidencial')
    end

    it 'deja crear una tarea en el tablero propio' do
      crear(title_jabvox: 'Legítima', board_id: board.id, stage_id: stage.id)

      expect(response).to have_http_status(:created)
    end
  end

  describe 'al editar' do
    let(:task) do
      account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id,
                                   title_jabvox: 'Mía', created_by_id: admin.id)
    end

    it 'no deja moverla al tablero de otra cuenta' do
      patch "#{tasks_url}/#{task.id}",
            params: { task: { board_id: other_board.id, stage_id: other_stage.id } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.board_id).to eq(board.id)
    end

    it 'no deja enlazarla a un contacto de otra cuenta' do
      patch "#{tasks_url}/#{task.id}", params: { task: { contact_id: other_contact.id } },
                                       headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.contact_id).to be_nil
    end
  end

  describe 'al leer' do
    it 'no encuentra una tarea de otra cuenta' do
      ajena = other_account.jabvox_tasks.create!(board_id: other_board.id, stage_id: other_stage.id,
                                                 title_jabvox: 'Ajena')

      get "#{tasks_url}/#{ajena.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'no lista tareas de otra cuenta' do
      other_account.jabvox_tasks.create!(board_id: other_board.id, stage_id: other_stage.id,
                                         title_jabvox: 'Ajena')
      account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id, title_jabvox: 'Mía')

      get tasks_url, headers: admin.create_new_auth_token, as: :json

      titulos = response.parsed_body.map { |t| t['title_jabvox'] }
      expect(titulos).to contain_exactly('Mía')
    end
  end
end
