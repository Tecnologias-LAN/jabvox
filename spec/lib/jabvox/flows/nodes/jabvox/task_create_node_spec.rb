# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.task.* — el bug de origen: un tablero de otra cuenta creaba una tarea
# huérfana. Aquí tablero, columna, responsables y fecha se validan antes.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::TaskCreateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Operaciones') }
  let(:stage) { crear_etapa(board, 'Pendiente', 0) }
  let(:otra_etapa) { crear_etapa(board, 'Hecho', 1) }

  def crear_etapa(tablero, nombre, posicion)
    account.jabvox_task_stages.create!(board: tablero, name_jabvox: nombre, position_jabvox: posicion)
  end

  def crear_usuario
    user = create(:user, account: account)
    account.users.reload
    user
  end

  # El lead ES el contacto (la tabla jabvox_leads ya no existe).
  def crear_lead(numero = 1)
    create(:contact, account: account, name: "Cliente #{numero}")
  end

  describe described_class do
    it 'crea la tarea en el tablero y la columna indicados' do
      result = run_node(described_class, ctx,
                        { 'title' => 'Llamar', 'boardId' => board.id, 'stageId' => stage.id,
                          'priority' => 'high', 'description' => 'Urgente' })

      expect(result).to be_ok
      task = account.jabvox_tasks.last
      expect(task.title_jabvox).to eq('Llamar')
      expect(task.stage_id).to eq(stage.id)
      expect(result.output['stage_name']).to eq('Pendiente')
      expect(result.output['board_name']).to eq('Operaciones')
      expect(result.output['priority']).to eq('high')
    end

    it 'sin columna elegida entra en la PRIMERA del tablero' do
      otra_etapa
      stage

      result = run_node(described_class, ctx, { 'title' => 'Llamar', 'boardId' => board.id, 'stageId' => '' })

      expect(result.output['stage_id']).to eq(stage.id)
    end

    it 'RECHAZA un tablero de otra cuenta en vez de crear una tarea huérfana' do
      ajeno = create(:account).jabvox_task_boards.create!(name_jabvox: 'Ajeno')

      result = run_node(described_class, ctx, { 'title' => 'Llamar', 'boardId' => ajeno.id })

      expect(result.error).to match(/no existe en esta cuenta/)
      expect(account.jabvox_tasks.count).to eq(0)
    end

    it 'rechaza una columna de OTRO tablero' do
      otro = account.jabvox_task_boards.create!(name_jabvox: 'Ventas')
      ajena = crear_etapa(otro, 'Nueva', 0)

      result = run_node(described_class, ctx,
                        { 'title' => 'Llamar', 'boardId' => board.id, 'stageId' => ajena.id })

      expect(result.error).to match(/pertenece a otro tablero/)
    end

    it 'exige el título' do
      expect(run_node(described_class, ctx, { 'title' => '', 'boardId' => board.id }).error)
        .to match(/Falta el título/)
    end

    it 'exige el tablero' do
      expect(run_node(described_class, ctx, { 'title' => 'Llamar', 'boardId' => '' }).error)
        .to match(/Falta el tablero/)
    end

    it 'falla si el tablero no tiene ninguna columna' do
      vacio = account.jabvox_task_boards.create!(name_jabvox: 'Vacío')

      expect(run_node(described_class, ctx, { 'title' => 'Llamar', 'boardId' => vacio.id }).error)
        .to match(/no tiene ninguna columna/)
    end

    it 'rechaza una prioridad fuera de la lista y dice cuáles valen' do
      result = run_node(described_class, ctx,
                        { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'priority' => 'altísima' })

      expect(result.error).to match(/prioridad.*altísima/)
      expect(result.error).to match(/low, normal, high, urgent/)
    end

    it 'rechaza un estado fuera de la lista' do
      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'status' => 'cerrada' }).error)
        .to match(/estado.*cerrada/)
    end

    it 'asigna la lista de responsables y deja el principal el primero' do
      principal = crear_usuario
      otro = crear_usuario

      result = run_node(described_class, ctx,
                        { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id,
                          'assigneeId' => principal.id, 'assigneeIds' => [otro.id] })

      expect(result.output['assignee_id']).to eq(principal.id)
      expect(result.output['assignee_ids']).to contain_exactly(principal.id, otro.id)
    end

    it 'AVISA de los responsables que no son de la cuenta en vez de ignorarlos' do
      ajeno = create(:user, account: create(:account))

      result = run_node(described_class, ctx,
                        { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'assigneeIds' => [ajeno.id] })

      expect(result.error).to match(/no son usuarios de esta cuenta: #{ajeno.id}/)
      expect(account.jabvox_tasks.count).to eq(0)
    end

    it 'guarda el vencimiento con fecha y hora' do
      result = run_node(described_class, ctx,
                        { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'due_date' => '2026-08-15 09:00' })

      expect(account.jabvox_tasks.last.due_at_jabvox).to eq(Time.zone.parse('2026-08-15 09:00'))
      expect(result.output['due_at']).to be_present
    end

    it 'FALLA con una fecha ilegible en vez de guardar la tarea sin vencimiento' do
      result = run_node(described_class, ctx,
                        { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'due_date' => 'el jueves' })

      expect(result.error).to match(/No se entiende la fecha de vencimiento/)
      expect(account.jabvox_tasks.count).to eq(0)
    end

    it 'vincula el lead cuando se indica y rechaza uno de otra cuenta' do
      lead = crear_lead

      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'leadId' => lead.id }).output['lead_id'])
        .to eq(lead.id)

      ajeno = create(:account)
      contacto = create(:contact, account: ajeno)
      lead_ajeno = contacto
      expect(run_node(described_class, ctx,
                      { 'title' => 'x', 'boardId' => board.id, 'stageId' => stage.id, 'leadId' => lead_ajeno.id }).error)
        .to match(/no existe en esta cuenta/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::TaskUpdateNode do
    let(:task) do
      account.jabvox_tasks.create!(board: board, stage: stage, title_jabvox: 'Original',
                                   description_jabvox: 'Desc')
    end

    it 'actualiza SOLO lo configurado y no vacía lo demás' do
      result = run_node(described_class, ctx, { 'taskId' => task.id, 'title' => 'Nuevo' })

      expect(result).to be_ok
      expect(task.reload.title_jabvox).to eq('Nuevo')
      expect(task.description_jabvox).to eq('Desc')
    end

    it 'falla si no se configuró nada que actualizar' do
      expect(run_node(described_class, ctx, { 'taskId' => task.id, 'title' => '' }).error)
        .to match(/ningún campo que actualizar/)
    end

    it 'mueve de columna validando que sea del tablero de la tarea' do
      result = run_node(described_class, ctx, { 'taskId' => task.id, 'stageId' => otra_etapa.id })

      expect(task.reload.stage_id).to eq(otra_etapa.id)
      expect(result.output['stage_name']).to eq('Hecho')
    end

    it 'rechaza una columna de otro tablero' do
      otro = account.jabvox_task_boards.create!(name_jabvox: 'Ventas')
      ajena = crear_etapa(otro, 'Nueva', 0)

      expect(run_node(described_class, ctx, { 'taskId' => task.id, 'stageId' => ajena.id }).error)
        .to match(/pertenece a otro tablero/)
    end

    it 'SUSTITUYE la lista de responsables por la configurada' do
      viejo = crear_usuario
      nuevo = crear_usuario
      task.sync_assignees!([viejo.id])

      result = run_node(described_class, ctx, { 'taskId' => task.id, 'assigneeIds' => [nuevo.id] })

      expect(result.output['assignee_ids']).to eq([nuevo.id])
      expect(task.reload.assignee_id).to eq(nuevo.id)
    end

    it 'valida el estado también al actualizar' do
      expect(run_node(described_class, ctx, { 'taskId' => task.id, 'status' => 'archivada' }).error)
        .to match(/estado.*archivada/)
    end

    it 'exige el ID de la tarea y avisa si no existe' do
      expect(run_node(described_class, ctx, { 'taskId' => '', 'title' => 'x' }).error)
        .to match(/Falta el ID de la tarea/)
      expect(run_node(described_class, ctx, { 'taskId' => 999_999, 'title' => 'x' }).error)
        .to match(/no existe en esta cuenta/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::TaskMoveNode do
    let(:task) { account.jabvox_tasks.create!(board: board, stage: stage, title_jabvox: 'T') }

    it 'mueve a la columna destino y devuelve de dónde venía' do
      result = run_node(described_class, ctx,
                        { 'taskId' => task.id, 'stageId' => otra_etapa.id, 'position' => 3 })

      expect(result).to be_ok
      expect(task.reload.stage_id).to eq(otra_etapa.id)
      expect(task.position_jabvox).to eq(3)
      expect(result.output['from_stage_name']).to eq('Pendiente')
      expect(result.output['moved']).to be(true)
    end

    it 'sin posición deja la tarjeta arriba del todo' do
      task.update!(position_jabvox: 7)

      run_node(described_class, ctx, { 'taskId' => task.id, 'stageId' => otra_etapa.id, 'position' => '' })

      expect(task.reload.position_jabvox).to eq(0)
    end

    it 'rechaza una etapa de otro tablero' do
      otro = account.jabvox_task_boards.create!(name_jabvox: 'Ventas')
      ajena = crear_etapa(otro, 'Nueva', 0)

      expect(run_node(described_class, ctx, { 'taskId' => task.id, 'stageId' => ajena.id }).error)
        .to match(/pertenece a otro tablero/)
    end

    it 'exige la columna destino' do
      expect(run_node(described_class, ctx, { 'taskId' => task.id, 'stageId' => '' }).error)
        .to match(/Falta la columna destino/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::TaskDeleteNode do
    let(:task) { account.jabvox_tasks.create!(board: board, stage: stage, title_jabvox: 'T') }

    it 'borra y devuelve datos para encadenar' do
      id = task.id

      result = run_node(described_class, ctx, { 'taskId' => id })

      expect(result.output).to include('deleted' => true, 'taskId' => id, 'title' => 'T')
      expect(account.jabvox_tasks.exists?(id)).to be(false)
    end

    it 'avisa cuando la tarea ya no existe' do
      expect(run_node(described_class, ctx, { 'taskId' => 999_999 }).error)
        .to match(/no existe en esta cuenta/)
    end
  end
end
