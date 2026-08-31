# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Nodos LEGACY de leads (list/get/find_by_date/find_by_field): reutilizan la
# lógica de jabvox.lead.search pero CONSERVAN su salida original.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::LeadListNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  def crear_lead(numero, campos: {}, nombre: nil, campana: nil, agente: nil)
    contact = create(:contact, account: account, name: nombre || "Cliente #{numero}",
                               phone_number: format('+5730055566%<n>02d', n: numero))
    account.jabvox_leads.create!(contact: contact, custom_fields_jabvox: campos,
                                 jabvox_campaign: campana, assignee: agente)
  end

  it 'declara itemsPath para que el bucle reciba la colección' do
    expect(described_class.node_items_path).to eq('leads')
  end

  it 'devuelve la salida legacy con leads y count' do
    crear_lead(1)
    crear_lead(2)

    result = run_node(described_class, ctx, {})

    expect(result.output['count']).to eq(2)
    expect(result.output['leads'].length).to eq(2)
    expect(result.output['page']).to eq(1)
  end

  it 'devuelve una colección vacía sin leads, sin fallar' do
    result = run_node(described_class, ctx, {})

    expect(result.ok?).to be(true)
    expect(result.output['leads']).to eq([])
    expect(result.output['count']).to eq(0)
  end

  it 'filtra por nombre del contacto con q' do
    crear_lead(1, nombre: 'Ana Pérez')
    crear_lead(2, nombre: 'Luis Gómez')

    result = run_node(described_class, ctx, { 'q' => 'ana' })

    expect(result.output['count']).to eq(1)
    expect(result.output['leads'].first['contact']['name']).to eq('Ana Pérez')
  end

  it 'filtra por campaña y por agente asignado' do
    campana = JabvoxCampaign.create!(account: account, name_jabvox: 'Verano')
    agente = create(:user, account: account)
    crear_lead(1, campana: campana, agente: agente)
    crear_lead(2)

    por_campana = run_node(described_class, ctx, { 'campaignId' => campana.id })
    por_agente = run_node(described_class, ctx, { 'assigneeId' => agente.id })

    expect(por_campana.output['count']).to eq(1)
    expect(por_agente.output['count']).to eq(1)
  end

  it 'ignora los filtros vacíos en vez de no encontrar nada' do
    crear_lead(1)

    result = run_node(described_class, ctx, { 'q' => '', 'campaignId' => '', 'assigneeId' => '', 'page' => '' })

    expect(result.output['count']).to eq(1)
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadGetNode do
    it 'devuelve el detalle PLANO de un lead' do
      lead = crear_lead(1, campos: { 'ciudad' => 'Cali' })

      result = run_node(described_class, ctx, { 'leadId' => lead.id })

      expect(result.output['id']).to eq(lead.id)
      expect(result.output['leadId']).to eq(lead.id)
      expect(result.output['custom_fields_jabvox']).to eq({ 'ciudad' => 'Cali' })
      expect(result.output).not_to have_key('leads')
    end

    it 'falla con un mensaje claro si el lead no existe' do
      result = run_node(described_class, ctx, { 'leadId' => 999_999 })

      expect(result.ok?).to be(false)
      expect(result.error).to match(/no existe en esta cuenta/)
    end

    it 'falla si falta el ID del lead' do
      expect(run_node(described_class, ctx, { 'leadId' => '' }).error)
        .to match(/Falta el ID interno del lead/)
    end

    it 'no encuentra un lead de OTRA cuenta' do
      otra = create(:account)
      contacto = create(:contact, account: otra)
      ajeno = otra.jabvox_leads.create!(contact: contacto)

      expect(run_node(described_class, ctx, { 'leadId' => ajeno.id }).ok?).to be(false)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadFindByFieldNode do
    it 'conserva la salida legacy { field, operator, value, leads, count }' do
      crear_lead(1, campos: { 'ciudad' => 'Bogotá' })
      crear_lead(2, campos: { 'ciudad' => 'Medellín' })

      result = run_node(described_class, ctx,
                        { 'field' => 'ciudad', 'operator' => 'contains', 'value' => 'bogo' })

      expect(result.output.keys).to match_array(%w[field operator value leads count])
      expect(result.output['count']).to eq(1)
      expect(result.output['field']).to eq('ciudad')
    end

    it 'devuelve 0 resultados sin fallar' do
      crear_lead(1, campos: { 'ciudad' => 'Bogotá' })

      result = run_node(described_class, ctx, { 'field' => 'ciudad', 'value' => 'quito' })

      expect(result.output['count']).to eq(0)
      expect(result.output['leads']).to eq([])
    end

    it 'falla si no se elige el campo' do
      expect(run_node(described_class, ctx, { 'field' => '', 'value' => 'x' }).error)
        .to match(/requiere elegir el campo/)
    end

    it 'declara itemsPath' do
      expect(described_class.node_items_path).to eq('leads')
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadFindByDateNode do
    it 'conserva la salida legacy con entity, field y targetDate' do
      crear_lead(1, campos: { 'cumple' => Date.current.strftime('%Y-%m-%d') })

      result = run_node(described_class, ctx,
                        { 'entity' => 'lead', 'field' => 'cumple', 'match' => 'today' })

      expect(result.output['entity']).to eq('lead')
      expect(result.output['field']).to eq('cumple')
      expect(result.output['targetDate']).to eq(Date.current.iso8601)
      expect(result.output['count']).to eq(1)
    end

    it 'aplica el signo NEGATIVO del offset con "hace N días"' do
      result = run_node(described_class, ctx,
                        { 'field' => 'cumple', 'match' => 'days_ago', 'offsetDays' => 3 })

      expect(result.output['targetDate']).to eq((Date.current - 3).iso8601)
    end

    it 'aplica el signo POSITIVO con "dentro de N días"' do
      result = run_node(described_class, ctx,
                        { 'field' => 'cumple', 'match' => 'in_days', 'offsetDays' => 3 })

      expect(result.output['targetDate']).to eq((Date.current + 3).iso8601)
    end

    it 'ignora el offset con "hoy"' do
      result = run_node(described_class, ctx,
                        { 'field' => 'cumple', 'match' => 'today', 'offsetDays' => 5 })

      expect(result.output['targetDate']).to eq(Date.current.iso8601)
    end

    it 'falla si falta el campo de fecha' do
      expect(run_node(described_class, ctx, { 'field' => '' }).error)
        .to match(/requiere el campo de fecha/)
    end
  end
end
