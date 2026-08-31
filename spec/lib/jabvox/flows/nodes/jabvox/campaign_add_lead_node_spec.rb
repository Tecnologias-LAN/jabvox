# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::CampaignAddLeadNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:contact) { create(:contact, account: account, name: 'Ana') }
  let(:lead) { account.jabvox_leads.create!(contact: contact) }

  it 'asocia el lead a una campaña NUEVA cuando se escribe un nombre libre' do
    result = run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => 'Navidad 2026' })

    expect(result).to be_ok
    expect(lead.reload.jabvox_campaign.name_jabvox).to eq('Navidad 2026')
    expect(result.output['campaign']).to eq('Navidad 2026')
  end

  it 'reutiliza la campaña existente con el mismo nombre en vez de duplicarla' do
    existente = account.jabvox_campaigns.create!(name_jabvox: 'Navidad 2026')

    run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => 'Navidad 2026' })

    expect(account.jabvox_campaigns.count).to eq(1)
    expect(lead.reload.jabvox_campaign_id).to eq(existente.id)
  end

  it 'resuelve el ID que entrega el select a NOMBRE de campaña' do
    campana = account.jabvox_campaigns.create!(name_jabvox: 'Verano')

    result = run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => campana.id.to_s })

    expect(result.output).to include('campaign' => 'Verano', 'campaign_id' => campana.id)
    expect(lead.reload.jabvox_campaign_id).to eq(campana.id)
  end

  it 'sustituye la campaña anterior del lead' do
    lead.update!(jabvox_campaign: account.jabvox_campaigns.create!(name_jabvox: 'Vieja'))

    run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => 'Nueva' })

    expect(lead.reload.jabvox_campaign.name_jabvox).to eq('Nueva')
  end

  it 'falla si la campaña llega vacía' do
    expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => '' }).error)
      .to match(/Falta la campaña/)
  end

  it 'falla si el ID del lead llega vacío' do
    expect(run_node(described_class, ctx, { 'leadId' => '', 'campaign' => 'X' }).error)
      .to match(/Falta el ID interno del lead/)
  end

  it 'rechaza un ID de campaña que no existe en la cuenta' do
    ajena = create(:account).jabvox_campaigns.create!(name_jabvox: 'Ajena')

    expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign' => ajena.id.to_s }).error)
      .to match(/no existe en esta cuenta/)
  end

  it 'no toca un lead de OTRA cuenta' do
    otra = create(:account)
    ajeno = otra.jabvox_leads.create!(contact: create(:contact, account: otra))

    expect(run_node(described_class, ctx, { 'leadId' => ajeno.id, 'campaign' => 'X' }).error)
      .to match(/no existe en esta cuenta/)
  end
end
