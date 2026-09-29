# frozen_string_literal: true

require 'rails_helper'

# Las columnas conservan su posición y su papel: editar una no debe reordenar el tablero
# ni perder si era la inicial, la de completadas o la de inactivas.
RSpec.describe 'Jabvox task stages', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: admin.id) }

  # Existe para que el tablero tenga las tres columnas del flujo real; los ejemplos
  # comprueban el orden y los roles del conjunto, no esta columna por su nombre.
  let!(:initial_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Por hacer',
                         position_jabvox: 0, role_jabvox: 'initial')
  end
  let!(:middle_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 1)
  end
  let!(:done_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Hecho',
                         position_jabvox: 2, role_jabvox: 'done')
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def stages_url = "/api/v1/accounts/#{account.id}/jabvox/tasks/boards/#{board.id}/stages"
  def stage_url(id) = "#{stages_url}/#{id}"

  it 'sirve las columnas ordenadas por posición' do
    get stages_url, headers: admin.create_new_auth_token, as: :json

    nombres = response.parsed_body.map { |s| s['name_jabvox'] }
    expect(nombres).to eq(['Por hacer', 'En curso', 'Hecho'])
  end

  it 'expone el papel de cada columna' do
    get stages_url, headers: admin.create_new_auth_token, as: :json

    roles = response.parsed_body.to_h { |s| [s['name_jabvox'], s['role_jabvox']] }
    expect(roles).to eq('Por hacer' => 'initial', 'En curso' => nil, 'Hecho' => 'done')
  end

  it 'renombrar no cambia la posición ni el papel' do
    patch stage_url(done_stage.id), params: { stage: { name_jabvox: 'Terminado' } },
                                    headers: admin.create_new_auth_token, as: :json

    done_stage.reload
    expect(done_stage.position_jabvox).to eq(2)
    expect(done_stage.role_jabvox).to eq('done')
  end

  it 'deja quitar el papel de una columna' do
    patch stage_url(done_stage.id), params: { stage: { role_jabvox: nil } },
                                    headers: admin.create_new_auth_token, as: :json

    expect(done_stage.reload.role_jabvox).to be_nil
  end

  it 'no deja dos columnas con el mismo papel, y lo dice en vez de reventar' do
    patch stage_url(middle_stage.id), params: { stage: { role_jabvox: 'done' } },
                                      headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].first).to match(/papel/i)
    expect(middle_stage.reload.role_jabvox).to be_nil
  end

  describe 'POST reorder' do
    def reorder_url = "#{stages_url}/reorder"

    def nombres_en_orden
      board.stages.ordered.pluck(:name_jabvox)
    end

    it 'reordena las columnas según los ids recibidos' do
      post reorder_url,
           params: { stage_ids: [done_stage.id, initial_stage.id, middle_stage.id] },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(nombres_en_orden).to eq(['Hecho', 'Por hacer', 'En curso'])
    end

    it 'devuelve las columnas ya reordenadas' do
      post reorder_url,
           params: { stage_ids: [middle_stage.id, done_stage.id, initial_stage.id] },
           headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.map { |s| s['name_jabvox'] })
        .to eq(['En curso', 'Hecho', 'Por hacer'])
    end

    it 'reordenar no cambia el papel de ninguna columna' do
      post reorder_url,
           params: { stage_ids: [done_stage.id, middle_stage.id, initial_stage.id] },
           headers: admin.create_new_auth_token, as: :json

      expect(initial_stage.reload.role_jabvox).to eq('initial')
      expect(done_stage.reload.role_jabvox).to eq('done')
    end

    # Seguridad: los ids vienen del cliente, así que todo lo que no sea del tablero
    # se descarta antes de tocar la base.
    it 'ignora ids de columnas de otro tablero' do
      otro_board = account.jabvox_task_boards.create!(name_jabvox: 'Otro', created_by_id: admin.id)
      ajena = otro_board.stages.create!(account_id: account.id, name_jabvox: 'Ajena',
                                        position_jabvox: 0)
      posicion_previa = ajena.position_jabvox

      post reorder_url, params: { stage_ids: [ajena.id, done_stage.id, initial_stage.id] },
                        headers: admin.create_new_auth_token, as: :json

      expect(ajena.reload.position_jabvox).to eq(posicion_previa)
      expect(nombres_en_orden.first).to eq('Hecho')
    end

    it 'no toca columnas de otra cuenta' do
      ajena_cuenta = create(:account)
      otro_board = ajena_cuenta.jabvox_task_boards.create!(name_jabvox: 'Ajeno')
      ajena = otro_board.stages.create!(account_id: ajena_cuenta.id, name_jabvox: 'Intrusa',
                                        position_jabvox: 7)

      post reorder_url, params: { stage_ids: [ajena.id, initial_stage.id] },
                        headers: admin.create_new_auth_token, as: :json

      expect(ajena.reload.position_jabvox).to eq(7)
    end

    it 'rechaza una lista vacía en vez de dejar el tablero a medias' do
      post reorder_url, params: { stage_ids: [] },
                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(nombres_en_orden).to eq(['Por hacer', 'En curso', 'Hecho'])
    end

    it 'descarta ids que no son números' do
      post reorder_url, params: { stage_ids: ['1); DROP TABLE jabvox_task_stages; --'] },
                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JabvoxTaskStage.where(id: board.stages.pluck(:id)).count).to eq(3)
    end

    it 'no se ahoga con una lista desmesurada' do
      ids = (1..5000).to_a + [done_stage.id, initial_stage.id]

      post reorder_url, params: { stage_ids: ids },
                        headers: admin.create_new_auth_token, as: :json

      # Se queda con los primeros MAX_STAGES, y de esos ninguno es del tablero.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(nombres_en_orden).to eq(['Por hacer', 'En curso', 'Hecho'])
    end

    it 'tolera que falte alguna columna en la lista' do
      post reorder_url, params: { stage_ids: [done_stage.id, initial_stage.id] },
                        headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(done_stage.reload.position_jabvox).to eq(0)
      expect(initial_stage.reload.position_jabvox).to eq(1)
    end

    # El gate solo actúa sobre roles personalizados: sin uno, se conserva el
    # comportamiento histórico (un agente normal gestiona columnas).
    it 'bloquea a un rol personalizado sin permiso de gestión' do
      agente = create(:user, account: account, role: :agent)
      rol = account.custom_roles.create!(name: 'Solo lectura', permissions: [])
      account.account_users.find_by(user: agente).update!(custom_role: rol)

      post reorder_url, params: { stage_ids: [done_stage.id, initial_stage.id] },
                        headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(nombres_en_orden).to eq(['Por hacer', 'En curso', 'Hecho'])
    end

    it 'no deja reordenar un tablero de otra cuenta' do
      ajena_cuenta = create(:account)
      otro_board = ajena_cuenta.jabvox_task_boards.create!(name_jabvox: 'Ajeno')

      post "/api/v1/accounts/#{account.id}/jabvox/tasks/boards/#{otro_board.id}/stages/reorder",
           params: { stage_ids: [initial_stage.id] },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'borra la columna' do
    delete stage_url(middle_stage.id), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(board.stages.pluck(:id)).not_to include(middle_stage.id)
  end

  # El backend borra en cascada: por eso el frontend avisa de cuántas se pierden.
  it 'borrar una columna se lleva sus tareas' do
    tarea = account.jabvox_tasks.create!(board_id: board.id, stage_id: middle_stage.id,
                                         title_jabvox: 'Se irá', created_by_id: admin.id)

    delete stage_url(middle_stage.id), headers: admin.create_new_auth_token, as: :json

    expect(JabvoxTask.where(id: tarea.id)).to be_empty
  end
end
