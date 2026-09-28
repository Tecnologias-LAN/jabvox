# frozen_string_literal: true

require 'rails_helper'

# Comentarios de resolución: se escriben desde la ficha sin entrar en modo edición y
# quedan en el mismo historial que los cambios de campos.
RSpec.describe 'Jabvox task comments', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: admin.id) }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 0)
  end
  let(:task) do
    account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id,
                                 title_jabvox: 'Revisar', created_by_id: admin.id)
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def comment_url(id) = "/api/v1/accounts/#{account.id}/jabvox/tasks/tasks/#{id}/comment"
  def activities_url(id) = "/api/v1/accounts/#{account.id}/jabvox/tasks/tasks/#{id}/activities"

  it 'guarda el comentario en el historial' do
    post comment_url(task.id), params: { body: 'Llamé al cliente, queda pendiente el pago' },
                               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['action']).to eq('comment')
    expect(response.parsed_body['metadata']['body']).to eq('Llamé al cliente, queda pendiente el pago')
  end

  it 'aparece en el historial junto al resto de actividad' do
    post comment_url(task.id), params: { body: 'Primer avance' },
                               headers: admin.create_new_auth_token, as: :json

    get activities_url(task.id), headers: admin.create_new_auth_token, as: :json

    acciones = response.parsed_body.map { |a| a['action'] }
    expect(acciones).to include('comment')
  end

  it 'rechaza un comentario vacío' do
    post comment_url(task.id), params: { body: '   ' },
                               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(task.activities.comments).to be_empty
  end

  # Comentar es parte de resolver, no de administrar el tablero: un agente que trabaja la
  # tarea puede comentarla aunque no pueda crear ni borrar tareas.
  it 'un agente puede comentar aunque no gestione tareas' do
    post comment_url(task.id), params: { body: 'Ya lo estoy viendo' },
                               headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
  end

  it 'registra quién lo escribió' do
    post comment_url(task.id), params: { body: 'Resuelto' },
                               headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['user_name']).to eq(agent.name)
  end

  it 'recorta un comentario desmesurado en vez de rechazarlo' do
    post comment_url(task.id), params: { body: 'a' * 6000 },
                               headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['metadata']['body'].length).to eq(JabvoxTaskActivity::MAX_COMMENT_LENGTH)
  end

  it 'no deja comentar una tarea de otra cuenta' do
    ajena = create(:account)
    otro_board = ajena.jabvox_task_boards.create!(name_jabvox: 'Otro')
    otra_stage = otro_board.stages.create!(account_id: ajena.id, name_jabvox: 'X', position_jabvox: 0)
    otra = ajena.jabvox_tasks.create!(board_id: otro_board.id, stage_id: otra_stage.id,
                                      title_jabvox: 'Ajena')

    post comment_url(otra.id), params: { body: 'No debería entrar' },
                               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
