# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.kanban.list — LECTURA de tarjetas de un embudo. Verifica el filtrado por
# embudo/columna, el enriquecimiento del contacto, el filtro por agente (que mira
# conversación o contacto) y que NO coloca tarjetas automáticamente.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::KanbanListNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:funnel) { account.jabvox_kanban_funnels.create!(name_jabvox: 'Ventas') }
  let(:stage_a) { crear_etapa('Nuevo', 0) }
  let(:stage_b) { crear_etapa('Negociación', 1) }

  def crear_etapa(nombre, pos)
    account.jabvox_kanban_stages.create!(jabvox_kanban_funnel: funnel, name_jabvox: nombre,
                                         position_jabvox: pos)
  end

  def colocar_contacto(contact, stage)
    JabvoxKanbanConversationStage.create!(account: account, jabvox_kanban_funnel: funnel,
                                          jabvox_kanban_stage: stage, contact: contact)
  end

  it 'lista todas las tarjetas del embudo con items_path cards' do
    colocar_contacto(create(:contact, account: account, name: 'Uno'), stage_a)
    colocar_contacto(create(:contact, account: account, name: 'Dos'), stage_b)

    result = run_node(described_class, ctx, { 'operation' => 'by_funnel', 'funnelId' => funnel.id })

    expect(result).to be_ok
    expect(result.output['count']).to eq(2)
    expect(result.output['funnel_name']).to eq('Ventas')
    expect(described_class.node_items_path).to eq('cards')
  end

  it 'filtra por una columna concreta' do
    colocar_contacto(create(:contact, account: account), stage_a)
    colocar_contacto(create(:contact, account: account), stage_b)

    result = run_node(described_class, ctx,
                      { 'operation' => 'by_stage', 'funnelId' => funnel.id, 'stageId' => stage_b.id })

    expect(result.output['count']).to eq(1)
    expect(result.output['stage_name']).to eq('Negociación')
    expect(result.output['cards'].first['stage_id']).to eq(stage_b.id)
  end

  it 'cada tarjeta trae la ficha completa del contacto (con atributos personalizados)' do
    contact = create(:contact, account: account, name: 'Ficha', custom_attributes: { 'origen' => 'web' })
    colocar_contacto(contact, stage_a)

    card = run_node(described_class, ctx,
                    { 'operation' => 'by_funnel', 'funnelId' => funnel.id }).output['cards'].first

    expect(card['contact']).to include('id' => contact.id, 'name' => 'Ficha')
    expect(card['contact']['custom_attributes']).to eq('origen' => 'web')
    expect(card).to have_key('assignee')
  end

  it 'filtra por agente mirando el responsable del contacto' do
    agent = create(:user, account: account)
    mine = create(:contact, account: account, assignee: agent)
    other = create(:contact, account: account)
    colocar_contacto(mine, stage_a)
    colocar_contacto(other, stage_a)

    result = run_node(described_class, ctx,
                      { 'operation' => 'by_funnel', 'funnelId' => funnel.id, 'assigneeId' => agent.id })

    expect(result.output['count']).to eq(1)
    expect(result.output['cards'].first['contact_id']).to eq(mine.id)
  end

  it 'exige la etapa en la operación by_stage' do
    expect(run_node(described_class, ctx, { 'operation' => 'by_stage', 'funnelId' => funnel.id }).error)
      .to match(/requiere elegir la etapa/)
  end

  it 'rechaza un embudo de otra cuenta' do
    ajeno = create(:account).jabvox_kanban_funnels.create!(name_jabvox: 'Ajeno')

    expect(run_node(described_class, ctx, { 'operation' => 'by_funnel', 'funnelId' => ajeno.id }).error)
      .to match(/no existe en esta cuenta/)
  end

  it 'NO coloca tarjetas: un embudo vacío devuelve lista vacía sin crear filas' do
    expect do
      result = run_node(described_class, ctx, { 'operation' => 'by_funnel', 'funnelId' => funnel.id })
      expect(result.output['count']).to eq(0)
    end.not_to change { JabvoxKanbanConversationStage.where(jabvox_kanban_funnel_id: funnel.id).count }
  end
end
