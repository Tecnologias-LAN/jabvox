# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.task.search — LECTURA de tareas. Verifica que los filtros se acotan a la
# cuenta, que la salida trae la ficha del contacto y del responsable, y que la
# paginación y los casos límite se comportan.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::TaskSearchNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:agent) { create(:user, account: account, name: 'Ana') }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Operaciones') }
  let(:stage_a) do
    account.jabvox_task_stages.create!(board: board, name_jabvox: 'Por hacer', position_jabvox: 0)
  end
  let(:stage_b) do
    account.jabvox_task_stages.create!(board: board, name_jabvox: 'En curso', position_jabvox: 1)
  end
  let(:contact) { create(:contact, account: account, name: 'Clienté Ñandú') }

  def crear_tarea(attrs = {})
    account.jabvox_tasks.create!({ board: board, stage: stage_a, title_jabvox: 'Tarea',
                                   status_jabvox: 'open', priority_jabvox: 'normal' }.merge(attrs))
  end

  it 'lista las tareas del tablero y normaliza la salida con items_path tasks' do
    crear_tarea(title_jabvox: 'Uno')
    crear_tarea(title_jabvox: 'Dos', stage: stage_b)

    result = run_node(described_class, ctx, { 'operation' => 'list', 'boardId' => board.id })

    expect(result).to be_ok
    expect(result.output['count']).to eq(2)
    expect(result.output['tasks'].map { |t| t['title'] }).to contain_exactly('Uno', 'Dos')
    expect(described_class.node_items_path).to eq('tasks')
  end

  it 'filtra por columna, estado, prioridad y responsable' do
    crear_tarea(stage: stage_b, status_jabvox: 'open', priority_jabvox: 'high', assignee: agent)
    crear_tarea(stage: stage_a, status_jabvox: 'done', priority_jabvox: 'low')

    result = run_node(described_class, ctx,
                      { 'operation' => 'list', 'boardId' => board.id, 'stageId' => stage_b.id,
                        'status' => 'open', 'priority' => 'high', 'assigneeId' => agent.id })

    expect(result.output['count']).to eq(1)
    expect(result.output['tasks'].first).to include('stage_id' => stage_b.id, 'priority' => 'high')
  end

  it 'filtra por rango de vencimiento' do
    crear_tarea(title_jabvox: 'Vencida', due_at_jabvox: 2.days.ago)
    crear_tarea(title_jabvox: 'Futura', due_at_jabvox: 5.days.from_now)

    result = run_node(described_class, ctx,
                      { 'operation' => 'list', 'dueTo' => Time.current.iso8601 })

    expect(result.output['tasks'].map { |t| t['title'] }).to eq(['Vencida'])
  end

  it 'incluye la ficha del contacto vinculado y del responsable en cada tarea' do
    crear_tarea(contact: contact, assignee: agent)

    result = run_node(described_class, ctx, { 'operation' => 'list' })
    task = result.output['tasks'].first

    expect(task['contact']).to include('id' => contact.id, 'name' => 'Clienté Ñandú')
    expect(task['contact']).to have_key('custom_attributes')
    expect(task['assignee']).to include('id' => agent.id, 'name' => 'Ana')
  end

  it 'obtiene una tarea concreta por su ID' do
    task = crear_tarea(title_jabvox: 'Concreta')

    result = run_node(described_class, ctx, { 'operation' => 'by_id', 'taskId' => task.id })

    expect(result).to be_ok
    expect(result.output['task']['title']).to eq('Concreta')
    expect(result.output['tasks'].length).to eq(1)
  end

  it 'pagina: respeta limit y marca hasMore' do
    3.times { |i| crear_tarea(title_jabvox: "T#{i}") }

    page1 = run_node(described_class, ctx, { 'operation' => 'list', 'limit' => 2, 'page' => 1 })
    page2 = run_node(described_class, ctx, { 'operation' => 'list', 'limit' => 2, 'page' => 2 })

    expect(page1.output['count']).to eq(2)
    expect(page1.output['hasMore']).to be(true)
    expect(page2.output['count']).to eq(1)
    expect(page2.output['hasMore']).to be(false)
  end

  it 'sin tareas devuelve lista vacía sin romper' do
    result = run_node(described_class, ctx, { 'operation' => 'list' })

    expect(result).to be_ok
    expect(result.output['count']).to eq(0)
    expect(result.output['tasks']).to eq([])
  end

  it 'trata un tablero de otra cuenta como inexistente' do
    ajeno = create(:account).jabvox_task_boards.create!(name_jabvox: 'Ajeno')

    expect(run_node(described_class, ctx, { 'operation' => 'list', 'boardId' => ajeno.id }).error)
      .to match(/no existe en esta cuenta/)
  end

  it 'falla al pedir una tarea por un ID inexistente' do
    expect(run_node(described_class, ctx, { 'operation' => 'by_id', 'taskId' => 999_999 }).error)
      .to match(/no existe en esta cuenta/)
  end
end
