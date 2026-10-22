# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.kanban.* — el bug de origen era la ambigüedad display_id vs PK: aquí la
# conversación se resuelve SIEMPRE por su display_id (el número de la URL).
RSpec.describe Jabvox::Flows::Nodes::Jabvox::KanbanMoveConversationNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:funnel) { account.jabvox_kanban_funnels.create!(name_jabvox: 'Ventas') }
  let(:stage) { crear_etapa(funnel, 'Nuevo', 0) }
  let(:otra_etapa) { crear_etapa(funnel, 'Ganado', 1) }

  def crear_etapa(embudo, nombre, posicion)
    account.jabvox_kanban_stages.create!(jabvox_kanban_funnel: embudo, name_jabvox: nombre,
                                         position_jabvox: posicion)
  end

  describe described_class do
    let(:conversation) { create(:conversation, account: account) }

    it 'coloca la conversación en la etapa resolviéndola por display_id' do
      result = run_node(described_class, ctx,
                        { 'funnelId' => funnel.id, 'stageId' => stage.id,
                          'conversationId' => conversation.display_id })

      expect(result).to be_ok
      row = JabvoxKanbanConversationStage.find(result.output['id'])
      expect(row.conversation_id).to eq(conversation.id)
      expect(row.jabvox_kanban_stage_id).to eq(stage.id)
      expect(result.output).to include('stage_name' => 'Nuevo', 'funnel_name' => 'Ventas',
                                       'conversation_id' => conversation.display_id)
    end

    it 'NO confunde el display_id con la PK interna' do
      # Se fuerza que la PK sea distinta del display_id creando otra conversación.
      create(:conversation, account: account)
      otra = create(:conversation, account: account)

      run_node(described_class, ctx,
               { 'funnelId' => funnel.id, 'stageId' => stage.id, 'conversationId' => otra.display_id })

      expect(JabvoxKanbanConversationStage.last.conversation_id).to eq(otra.id)
    end

    it 'reutiliza la fila del embudo al mover otra vez (unicidad por conversación+embudo)' do
      run_node(described_class, ctx,
               { 'funnelId' => funnel.id, 'stageId' => stage.id,
                 'conversationId' => conversation.display_id })

      result = run_node(described_class, ctx,
                        { 'funnelId' => funnel.id, 'stageId' => otra_etapa.id,
                          'conversationId' => conversation.display_id })

      expect(JabvoxKanbanConversationStage.count).to eq(1)
      expect(result.output['from_stage_name']).to eq('Nuevo')
      expect(result.output['stage_name']).to eq('Ganado')
    end

    it 'rechaza una etapa de OTRO embudo con un mensaje legible' do
      otro = account.jabvox_kanban_funnels.create!(name_jabvox: 'Soporte')
      ajena = crear_etapa(otro, 'Abierto', 0)

      result = run_node(described_class, ctx,
                        { 'funnelId' => funnel.id, 'stageId' => ajena.id,
                          'conversationId' => conversation.display_id })

      expect(result.error).to match(/pertenece a otro embudo/)
      expect(JabvoxKanbanConversationStage.count).to eq(0)
    end

    it 'rechaza un embudo de otra cuenta' do
      ajeno = create(:account).jabvox_kanban_funnels.create!(name_jabvox: 'Ajeno')

      expect(run_node(described_class, ctx,
                      { 'funnelId' => ajeno.id, 'stageId' => stage.id,
                        'conversationId' => conversation.display_id }).error)
        .to match(/embudo #{ajeno.id} no existe/)
    end

    it 'exige el embudo y la etapa' do
      expect(run_node(described_class, ctx, { 'funnelId' => '', 'stageId' => stage.id }).error)
        .to match(/Falta el embudo/)
      expect(run_node(described_class, ctx, { 'funnelId' => funnel.id, 'stageId' => '' }).error)
        .to match(/Falta la etapa destino/)
    end

    it 'avisa cuando la conversación no existe en la cuenta' do
      expect(run_node(described_class, ctx,
                      { 'funnelId' => funnel.id, 'stageId' => stage.id, 'conversationId' => 999_999 }).error)
        .to match(/La conversación 999999 no existe/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::KanbanMoveLeadNode do
    let(:lead) do
      create(:contact, account: account, name: 'Cliente')
    end

    it 'coloca el lead en la etapa del embudo' do
      result = run_node(described_class, ctx,
                        { 'funnelId' => funnel.id, 'stageId' => stage.id, 'leadId' => lead.id })

      expect(result).to be_ok
      row = JabvoxKanbanConversationStage.find(result.output['id'])
      expect(row.contact_id).to eq(lead.id)
      expect(result.output).to include('lead_id' => lead.id, 'lead_number' => nil,
                                       'stage_name' => 'Nuevo')
    end

    it 'reutiliza la fila del embudo al mover el lead otra vez' do
      run_node(described_class, ctx, { 'funnelId' => funnel.id, 'stageId' => stage.id, 'leadId' => lead.id })

      result = run_node(described_class, ctx,
                        { 'funnelId' => funnel.id, 'stageId' => otra_etapa.id, 'leadId' => lead.id })

      expect(JabvoxKanbanConversationStage.count).to eq(1)
      expect(result.output['from_stage_name']).to eq('Nuevo')
      expect(result.output['moved']).to be(true)
    end

    it 'rechaza una etapa de otro embudo' do
      otro = account.jabvox_kanban_funnels.create!(name_jabvox: 'Soporte')
      ajena = crear_etapa(otro, 'Abierto', 0)

      expect(run_node(described_class, ctx,
                      { 'funnelId' => funnel.id, 'stageId' => ajena.id, 'leadId' => lead.id }).error)
        .to match(/pertenece a otro embudo/)
    end

    it 'exige el ID del lead y avisa si no está en la cuenta' do
      expect(run_node(described_class, ctx,
                      { 'funnelId' => funnel.id, 'stageId' => stage.id, 'leadId' => '' }).error)
        .to match(/Falta el ID del contacto/)
      expect(run_node(described_class, ctx,
                      { 'funnelId' => funnel.id, 'stageId' => stage.id, 'leadId' => 999_999 }).error)
        .to match(/El contacto 999999 no existe/)
    end
  end
end
