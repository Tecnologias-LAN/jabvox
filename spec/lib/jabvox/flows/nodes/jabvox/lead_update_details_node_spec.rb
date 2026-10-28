# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Nodos de ESCRITURA sobre leads: actualizar, fijar campo, asignar/desasignar
# y sincronizar contactos.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::LeadUpdateDetailsNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  # Los "leads" hoy SON contactos (la tabla jabvox_leads ya no existe): el lead es
  # el propio contacto y sus campos personalizados viven en custom_fields_jabvox.
  def crear_lead(numero, campos: {}, nombre: nil)
    create(:contact, account: account, name: nombre || "Cliente #{numero}",
                     phone_number: format('+5730077788%<n>02d', n: numero),
                     custom_fields_jabvox: campos)
  end

  it 'actualiza teléfono y email del contacto y devuelve el lead REAL releído' do
    lead = crear_lead(1)

    result = run_node(described_class, ctx,
                      { 'leadId' => lead.id, 'phone_number' => '+573009998877',
                        'email' => 'nuevo@ejemplo.com' })

    expect(result.output['updated']).to be(true)
    expect(result.output['id']).to eq(lead.id)
    expect(result.output['contact']['phone_number']).to eq('+573009998877')
    expect(result.output['contact']['email']).to eq('nuevo@ejemplo.com')
  end

  it 'guarda país y documento en los atributos adicionales del contacto' do
    lead = crear_lead(1)

    run_node(described_class, ctx,
             { 'leadId' => lead.id, 'country' => 'CO', 'identification' => '1020304050' })

    adicionales = lead.reload.additional_attributes
    expect(adicionales['country']).to eq('CO')
    expect(adicionales['jabvox_identification_number']).to eq('1020304050')
  end

  it 'NO toca los campos que se dejan vacíos' do
    lead = crear_lead(1)
    telefono = lead.phone_number

    run_node(described_class, ctx, { 'leadId' => lead.id, 'phone_number' => '', 'email' => '' })

    expect(lead.reload.phone_number).to eq(telefono)
  end

  context 'with the companies module (empresa entidad)' do
    before { account.enable_features!('companies') }

    let(:company) { create(:company, account: account) }

    it 'liga el contacto a una empresa de la cuenta' do
      lead = crear_lead(1)
      run_node(described_class, ctx, { 'leadId' => lead.id, 'companyId' => company.id })
      expect(lead.reload.company_id).to eq(company.id)
    end

    it 'desvincula la empresa con "nil"' do
      lead = crear_lead(1)
      lead.update!(company: company)
      run_node(described_class, ctx, { 'leadId' => lead.id, 'companyId' => 'nil' })
      expect(lead.reload.company_id).to be_nil
    end

    it 'rechaza una empresa de otra cuenta' do
      lead = crear_lead(1)
      ajena = create(:company, account: create(:account))
      expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'companyId' => ajena.id }).error)
        .to match(/no pertenece a esta cuenta/)
      expect(lead.reload.company_id).to be_nil
    end

    it 'no hace nada si el módulo de empresas está desactivado' do
      account.disable_features!('companies')
      lead = crear_lead(1)
      run_node(described_class, ctx, { 'leadId' => lead.id, 'companyId' => company.id })
      expect(lead.reload.company_id).to be_nil
    end
  end

  it 'crea la campaña si no existe y la asigna al lead' do
    lead = crear_lead(1)

    result = run_node(described_class, ctx, { 'leadId' => lead.id, 'campaign_name' => 'Otoño' })

    expect(result.output['campaign']).to eq('Otoño')
    expect(account.jabvox_campaigns.find_by(name_jabvox: 'Otoño')).to be_present
  end

  it 'asigna el agente indicado' do
    lead = crear_lead(1)
    agente = create(:user, account: account)

    result = run_node(described_class, ctx, { 'leadId' => lead.id, 'assigneeId' => agente.id })

    expect(lead.reload.assignee_id).to eq(agente.id)
    expect(result.output['assignee_name']).to eq(agente.name)
  end

  it 'FUSIONA los campos personalizados en vez de reemplazarlos' do
    lead = crear_lead(1, campos: { 'ciudad' => 'Cali', 'plan' => 'oro' })

    result = run_node(described_class, ctx,
                      { 'leadId' => lead.id, 'custom_fields' => { 'ciudad' => 'Bogotá' } })

    expect(result.output['custom_fields_jabvox']).to eq({ 'ciudad' => 'Bogotá', 'plan' => 'oro' })
  end

  it 'acepta los campos personalizados en JSON de texto (flujos antiguos)' do
    lead = crear_lead(1, campos: { 'plan' => 'oro' })

    result = run_node(described_class, ctx,
                      { 'leadId' => lead.id, 'custom_fields' => '{"ciudad":"Cali"}' })

    expect(result.output['custom_fields_jabvox']).to eq({ 'plan' => 'oro', 'ciudad' => 'Cali' })
  end

  it 'falla claro si los campos personalizados no son un JSON válido' do
    lead = crear_lead(1)

    expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'custom_fields' => 'no soy json' }).error)
      .to match(/no son válidos/)
  end

  it 'falla si falta el ID interno del lead' do
    expect(run_node(described_class, ctx, { 'leadId' => '' }).error)
      .to match(/Falta el ID interno del lead/)
  end

  it 'falla si el lead no existe en la cuenta' do
    expect(run_node(described_class, ctx, { 'leadId' => 999_999, 'email' => 'a@b.com' }).error)
      .to match(/no existe en esta cuenta/)
  end

  it 'falla si el agente no pertenece a la cuenta' do
    lead = crear_lead(1)
    ajeno = create(:user, account: create(:account))

    expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'assigneeId' => ajeno.id }).error)
      .to match(/no pertenece a esta cuenta/)
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadSetCustomFieldsNode do
    it 'FUSIONA el campo sobre los que ya existen' do
      lead = crear_lead(1, campos: { 'plan' => 'oro', 'ciudad' => 'Cali' })

      result = run_node(described_class, ctx,
                        { 'leadId' => lead.id, 'field' => 'ciudad', 'value' => 'Bogotá' })

      expect(result.output['custom_fields_jabvox']).to eq({ 'plan' => 'oro', 'ciudad' => 'Bogotá' })
      expect(result.output['updated']).to be(true)
    end

    it 'falla si no se elige el campo' do
      lead = crear_lead(1)

      expect(run_node(described_class, ctx, { 'leadId' => lead.id, 'field' => '', 'value' => 'x' }).error)
        .to match(/Elige el campo personalizado/)
    end

    it 'falla si el lead no existe' do
      expect(run_node(described_class, ctx, { 'leadId' => 999_999, 'field' => 'ciudad', 'value' => 'x' }).error)
        .to match(/no existe en esta cuenta/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadAssignNode do
    it 'asigna varios leads y no reporta ids faltantes' do
      agente = create(:user, account: account)
      uno = crear_lead(1)
      dos = crear_lead(2)

      result = run_node(described_class, ctx,
                        { 'leadIds' => "#{uno.id},#{dos.id}", 'assigneeId' => agente.id })

      expect(result.output['assigned']).to eq(2)
      expect(result.output['requested']).to eq(2)
      expect(result.output['missingIds']).to eq([])
      expect(result.output).not_to have_key('warning')
      expect([uno, dos].map { |l| l.reload.assignee_id }).to all(eq(agente.id))
    end

    it 'AVISA de los ids que no existen en la cuenta (bug corregido)' do
      agente = create(:user, account: account)
      uno = crear_lead(1)

      result = run_node(described_class, ctx,
                        { 'leadIds' => [uno.id, 999_999], 'assigneeId' => agente.id })

      expect(result.output['assigned']).to eq(1)
      expect(result.output['missingIds']).to eq([999_999])
      expect(result.output['notFound']).to eq(1)
      expect(result.output['warning']).to match(/no existen en esta cuenta/)
    end

    it 'trata un lead de OTRA cuenta como inexistente' do
      agente = create(:user, account: account)
      otra = create(:account)
      ajeno = create(:contact, account: otra)

      result = run_node(described_class, ctx, { 'leadIds' => ajeno.id, 'assigneeId' => agente.id })

      expect(result.output['assigned']).to eq(0)
      expect(result.output['missingIds']).to eq([ajeno.id])
      expect(ajeno.reload.assignee_id).to be_nil
    end

    it 'falla si la lista de leads viene vacía' do
      agente = create(:user, account: account)

      expect(run_node(described_class, ctx, { 'leadIds' => '', 'assigneeId' => agente.id }).error)
        .to match(/al menos un ID interno de lead/)
    end

    it 'falla si el agente no pertenece a la cuenta' do
      lead = crear_lead(1)
      ajeno = create(:user, account: create(:account))

      expect(run_node(described_class, ctx, { 'leadIds' => lead.id, 'assigneeId' => ajeno.id }).error)
        .to match(/no pertenece a esta cuenta/)
    end

    it 'falla si falta el agente' do
      lead = crear_lead(1)

      expect(run_node(described_class, ctx, { 'leadIds' => lead.id, 'assigneeId' => '' }).error)
        .to match(/Falta el agente a asignar/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::LeadUnassignNode do
    it 'quita el agente de los leads pedidos' do
      agente = create(:user, account: account)
      lead = crear_lead(1)
      lead.update!(assignee: agente)

      result = run_node(described_class, ctx, { 'leadIds' => lead.id })

      expect(result.output['unassigned']).to eq(1)
      expect(lead.reload.assignee_id).to be_nil
    end

    it 'AVISA de los ids que no existen' do
      lead = crear_lead(1)

      result = run_node(described_class, ctx, { 'leadIds' => "#{lead.id},999999" })

      expect(result.output['unassigned']).to eq(1)
      expect(result.output['missingIds']).to eq([999_999])
    end

    it 'falla si la lista viene vacía' do
      expect(run_node(described_class, ctx, { 'leadIds' => '' }).error)
        .to match(/al menos un ID interno de lead/)
    end
  end
end
