# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox tasks trash', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero') }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Pendiente', position_jabvox: 0)
  end
  let(:task) do
    account.jabvox_tasks.create!(
      board_id: board.id,
      stage_id: stage.id,
      title_jabvox: 'Llamar al contacto'
    )
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def tasks_url = "/api/v1/accounts/#{account.id}/jabvox/tasks/tasks"

  it 'mueve tareas eliminadas a la papelera y permite restaurarlas' do
    delete "#{tasks_url}/#{task.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(task.reload.deleted_at_jabvox).to be_present

    get tasks_url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to be_empty

    get tasks_url, params: { deleted: true }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.pluck('id')).to eq([task.id])

    post "#{tasks_url}/#{task.id}/restore", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(task.reload.deleted_at_jabvox).to be_nil
  end

  it 'no permite recuperar tareas de otra cuenta' do
    other_account = create(:account, jabvox_tasks_enabled_jabvox: true)
    other_board = other_account.jabvox_task_boards.create!(name_jabvox: 'Ajeno')
    other_stage = other_board.stages.create!(
      account_id: other_account.id,
      name_jabvox: 'Pendiente',
      position_jabvox: 0
    )
    foreign_task = other_account.jabvox_tasks.create!(
      board_id: other_board.id,
      stage_id: other_stage.id,
      title_jabvox: 'Tarea ajena',
      deleted_at_jabvox: Time.current
    )

    post "#{tasks_url}/#{foreign_task.id}/restore",
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'filtra las tareas por estado y mantiene separada la papelera' do
    completed_task = account.jabvox_tasks.create!(
      board_id: board.id,
      stage_id: stage.id,
      title_jabvox: 'Completada',
      status_jabvox: 'done'
    )
    task.update!(deleted_at_jabvox: Time.current)

    get tasks_url, params: { status: 'done' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.pluck('id')).to eq([completed_task.id])
  end
end
