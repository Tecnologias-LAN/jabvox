# frozen_string_literal: true

require 'rails_helper'

# Copia de una tarea al tablero personal del responsable: al asignar a alguien que es
# dueño de tablero, la tarea se duplica en el tablero suyo que se haya configurado.
RSpec.describe 'Jabvox task assignee board copy', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:foreign_admin) { create(:user, account: other_account, role: :administrator) }

  let(:source) do
    account.jabvox_task_boards.create!(name_jabvox: 'Operaciones', created_by_id: admin.id,
                                       copy_to_assignee_board_jabvox: true)
  end
  let(:source_stage) do
    source.stages.create!(account_id: account.id, name_jabvox: 'Nuevas',
                          role_jabvox: 'initial', position_jabvox: 0)
  end
  let(:personal) do
    account.jabvox_task_boards.create!(name_jabvox: 'Tablero de Ana', created_by_id: admin.id,
                                       owner_id: agent.id)
  end
  let!(:personal_stage) do
    personal.stages.create!(account_id: account.id, name_jabvox: 'Por hacer',
                            role_jabvox: 'initial', position_jabvox: 0)
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def targets_url(board_id) = "/api/v1/accounts/#{account.id}/jabvox/tasks/boards/#{board_id}/assignee_board_targets"

  def new_task
    account.jabvox_tasks.create!(board_id: source.id, stage_id: source_stage.id,
                                 title_jabvox: 'Llamar al cliente', created_by_id: admin.id)
  end

  def configure_target!
    JabvoxTaskAssigneeBoardTarget.create!(account: account, source_board: source,
                                          owner: agent, target_board: personal)
  end

  describe 'la copia' do
    it 'crea la tarea en el tablero del responsable, en su columna inicial' do
      configure_target!
      task = new_task

      expect { task.sync_assignees!([agent.id]) }.to change { personal.tasks.count }.by(1)

      copy = personal.tasks.last
      expect(copy.title_jabvox).to eq('Llamar al cliente')
      expect(copy.stage_id).to eq(personal_stage.id)
      expect(copy.assignee_id).to eq(agent.id)
      expect(copy.source_task_id).to eq(task.id)
    end

    it 'no duplica la copia al reasignar el mismo responsable' do
      configure_target!
      task = new_task
      task.sync_assignees!([agent.id])
      task.sync_assignees!([])

      expect { task.sync_assignees!([agent.id]) }.not_to(change { personal.tasks.count })
    end

    it 'no copia si el tablero de origen no lo tiene activado' do
      configure_target!
      source.update!(copy_to_assignee_board_jabvox: false)
      task = new_task

      expect { task.sync_assignees!([agent.id]) }.not_to(change { personal.tasks.count })
    end

    it 'copia al tablero propio del responsable sin configurar destino' do
      # El destino se deduce: si el agente tiene tablero, ese es el suyo. Exigir una fila
      # de configuración hacía que la automatización no hiciera nada y sin decir por qué.
      task = new_task

      expect { task.sync_assignees!([agent.id]) }
        .to change { personal.tasks.count }.by(1)
    end

    it 'respeta el destino configurado cuando el responsable tiene varios tableros' do
      second = account.jabvox_task_boards.create!(name_jabvox: 'Otro de Ana',
                                                  created_by_id: admin.id, owner_id: agent.id)
      second.stages.create!(account_id: account.id, name_jabvox: 'Por hacer',
                            role_jabvox: 'initial', position_jabvox: 0)
      JabvoxTaskAssigneeBoardTarget.create!(account: account, source_board: source,
                                            owner: agent, target_board: second)
      task = new_task

      expect { task.sync_assignees!([agent.id]) }.to change { second.tasks.count }.by(1)
      expect(personal.tasks.count).to eq(0)
    end

    it 'no copia a un responsable que no tiene ningún tablero propio' do
      no_board = create(:user, account: account, role: :agent)
      task = new_task

      expect { task.sync_assignees!([no_board.id]) }.not_to change(JabvoxTask, :count)
    end

    it 'no copia al responsable cuyo destino es el propio tablero de origen' do
      # Ya tiene la tarea delante: copiársela le dejaría dos iguales en la misma pantalla.
      source.update!(owner_id: agent.id)
      JabvoxTaskAssigneeBoardTarget.create!(account: account, source_board: source,
                                            owner: agent, target_board: source)
      task = new_task

      expect { task.sync_assignees!([agent.id]) }.not_to change(JabvoxTask, :count)
    end

    it 'copia también al dueño del tablero de origen aunque no sea responsable' do
      other_agent = create(:user, account: account, role: :agent)
      source.update!(owner_id: agent.id)
      configure_target!
      task = new_task

      expect { task.sync_assignees!([other_agent.id]) }
        .to change { personal.tasks.count }.by(1)
      expect(personal.tasks.last.assignee_id).to eq(agent.id)
    end

    it 'no encadena copias: la copia no vuelve a copiarse' do
      configure_target!
      task = new_task
      task.sync_assignees!([agent.id])
      copy = personal.tasks.last

      expect { copy.sync_assignees!([agent.id]) }.not_to change(JabvoxTask, :count)
    end
  end

  describe 'configuración de destinos' do
    it 'el admin puede crear un destino' do
      post targets_url(source.id),
           params: { target: { owner_id: agent.id, target_board_id: personal.id } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['target_board_id']).to eq(personal.id)
    end

    it 'rechaza un destino que no es del responsable indicado' do
      ajeno = account.jabvox_task_boards.create!(name_jabvox: 'Sin dueño', created_by_id: admin.id)

      post targets_url(source.id),
           params: { target: { owner_id: agent.id, target_board_id: ajeno.id } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza un destino de otra cuenta' do
      foreign_board = other_account.jabvox_task_boards.create!(
        name_jabvox: 'Ajeno', created_by_id: foreign_admin.id, owner_id: agent.id
      )

      post targets_url(source.id),
           params: { target: { owner_id: agent.id, target_board_id: foreign_board.id } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'no deja ver ni tocar los destinos de un tablero de otra cuenta' do
      foreign_board = other_account.jabvox_task_boards.create!(
        name_jabvox: 'Ajeno', created_by_id: foreign_admin.id
      )

      get targets_url(foreign_board.id), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'un agente sin rol no puede configurar destinos' do
      post targets_url(source.id),
           params: { target: { owner_id: agent.id, target_board_id: personal.id } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).not_to have_http_status(:created)
    end
  end

  describe 'dueño del tablero' do
    it 'ignora un dueño que no pertenece a la cuenta' do
      patch "/api/v1/accounts/#{account.id}/jabvox/tasks/boards/#{source.id}",
            params: { board: { owner_id: foreign_admin.id } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(source.reload.owner_id).to be_nil
    end
  end
end
