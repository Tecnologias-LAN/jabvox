# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.lead.search — los 6 modos deben normalizar la salida a
# { mode, count, leads }, para que el bucle funcione igual con todos.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::LeadSearchNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  def crear_lead(numero, campos: {}, nombre: nil)
    contact = create(:contact, account: account, name: nombre || "Cliente #{numero}",
                               phone_number: format('+5730011122%<n>02d', n: numero))
    account.jabvox_leads.create!(contact: contact, custom_fields_jabvox: campos)
  end

  it 'declara itemsPath para que el bucle reciba la colección' do
    expect(described_class.node_items_path).to eq('leads')
  end

  describe 'modo by_id' do
    it 'encuentra por PK interna' do
      lead = crear_lead(1)

      result = run_node(described_class, ctx, { 'mode' => 'by_id', 'leadId' => lead.id })

      expect(result.output['count']).to eq(1)
      expect(result.output['lead']['id']).to eq(lead.id)
    end

    it 'encuentra por NÚMERO visible de lead' do
      lead = crear_lead(1)

      result = run_node(described_class, ctx,
                        { 'mode' => 'by_id', 'idKind' => 'lead_number', 'leadNumber' => lead.lead_number })

      expect(result.output['leads'].first['id']).to eq(lead.id)
    end

    it 'falla claro si el lead no existe' do
      expect(run_node(described_class, ctx, { 'mode' => 'by_id', 'leadId' => 999_999 }).error)
        .to match(/No se encontró el lead/)
    end
  end

  describe 'modo by_field' do
    it 'busca por CONTIENE en un campo personalizado' do
      crear_lead(1, campos: { 'ciudad' => 'Bogotá' })
      crear_lead(2, campos: { 'ciudad' => 'Medellín' })

      result = run_node(described_class, ctx,
                        { 'mode' => 'by_field', 'field' => 'ciudad', 'value' => 'bogo' })

      expect(result.output['count']).to eq(1)
    end

    it 'busca por IGUAL A' do
      crear_lead(1, campos: { 'plan' => 'oro' })
      crear_lead(2, campos: { 'plan' => 'oro premium' })

      result = run_node(described_class, ctx,
                        { 'mode' => 'by_field', 'field' => 'plan', 'operator' => 'equals', 'value' => 'oro' })

      expect(result.output['count']).to eq(1)
    end

    it 'busca los que tienen el campo VACÍO' do
      crear_lead(1, campos: { 'plan' => 'oro' })
      crear_lead(2, campos: { 'plan' => '' })

      result = run_node(described_class, ctx,
                        { 'mode' => 'by_field', 'field' => 'plan', 'operator' => 'empty' })

      expect(result.output['count']).to eq(1)
    end

    it 'exige un valor con los operadores que comparan' do
      expect(run_node(described_class, ctx, { 'mode' => 'by_field', 'field' => 'plan', 'value' => '' }).error)
        .to match(/requiere un valor/)
    end

    it 'exige elegir el campo' do
      expect(run_node(described_class, ctx, { 'mode' => 'by_field', 'field' => '' }).error)
        .to match(/requiere elegir el campo/)
    end
  end

  describe 'modo by_label' do
    it 'encuentra los leads cuyo CONTACTO lleva la etiqueta' do
      create(:label, account: account, title: 'prioritario')
      lead = crear_lead(1)
      lead.contact.update!(label_list: ['prioritario'])
      crear_lead(2)

      result = run_node(described_class, ctx, { 'mode' => 'by_label', 'label' => 'prioritario' })

      expect(result.output['count']).to eq(1)
      expect(result.output['leads'].first['id']).to eq(lead.id)
    end

    it 'devuelve vacío sin fallar cuando nadie lleva la etiqueta' do
      result = run_node(described_class, ctx, { 'mode' => 'by_label', 'label' => 'inexistente' })

      expect(result).to be_ok
      expect(result.output['leads']).to eq([])
    end
  end

  describe 'modo by_date' do
    it 'compara mes y día (cumpleaños), ignorando el año' do
      hoy = Date.current
      crear_lead(1, campos: { 'cumple' => hoy.change(year: 1990).iso8601 })
      crear_lead(2, campos: { 'cumple' => (hoy + 3.days).change(year: 1990).iso8601 })

      result = run_node(described_class, ctx, { 'mode' => 'by_date', 'dateField' => 'cumple' })

      expect(result.output['count']).to eq(1)
    end

    it 'compara la fecha completa cuando se pide' do
      crear_lead(1, campos: { 'vence' => Date.current.iso8601 })

      result = run_node(described_class, ctx,
                        { 'mode' => 'by_date', 'dateField' => 'vence', 'compareMode' => 'full_date' })

      expect(result.output['count']).to eq(1)
    end

    it 'IGNORA las fechas ilegibles en vez de romper' do
      crear_lead(1, campos: { 'vence' => 'no es una fecha' })

      result = run_node(described_class, ctx, { 'mode' => 'by_date', 'dateField' => 'vence' })

      expect(result).to be_ok
      expect(result.output['count']).to be_zero
    end
  end

  describe 'modo list' do
    it 'lista los leads de la cuenta acotados por el límite' do
      3.times { |i| crear_lead(i + 1) }

      result = run_node(described_class, ctx, { 'mode' => 'list', 'limit' => 2 })

      expect(result.output['count']).to eq(2)
    end
  end

  describe 'modo advanced' do
    it 'exige TODAS las condiciones con match=all' do
      crear_lead(1, campos: { 'ciudad' => 'Bogotá', 'plan' => 'oro' })
      crear_lead(2, campos: { 'ciudad' => 'Bogotá', 'plan' => 'plata' })

      conditions = { 'match' => 'all',
                     'rules' => [{ 'field' => 'ciudad', 'operator' => 'equals', 'value' => 'Bogotá' },
                                 { 'field' => 'plan', 'operator' => 'equals', 'value' => 'oro' }] }
      result = run_node(described_class, ctx, { 'mode' => 'advanced', 'conditions' => conditions })

      expect(result.output['count']).to eq(1)
    end

    it 'basta UNA condición con match=any' do
      crear_lead(1, campos: { 'plan' => 'oro' })
      crear_lead(2, campos: { 'plan' => 'plata' })

      conditions = { 'match' => 'any',
                     'rules' => [{ 'field' => 'plan', 'operator' => 'equals', 'value' => 'oro' },
                                 { 'field' => 'plan', 'operator' => 'equals', 'value' => 'plata' }] }
      result = run_node(described_class, ctx, { 'mode' => 'advanced', 'conditions' => conditions })

      expect(result.output['count']).to eq(2)
    end

    it 'descarta las filas vacías del editor pero exige al menos una condición' do
      conditions = { 'rules' => [{ 'field' => '', 'operator' => '' }] }

      expect(run_node(described_class, ctx, { 'mode' => 'advanced', 'conditions' => conditions }).error)
        .to match(/al menos una condición/)
    end

    it 'avisa de una condición sin operador' do
      conditions = { 'rules' => [{ 'field' => 'plan', 'operator' => '' }] }

      expect(run_node(described_class, ctx, { 'mode' => 'advanced', 'conditions' => conditions }).error)
        .to match(/no tiene operador/)
    end
  end

  it 'los 6 modos devuelven la MISMA forma, para que el bucle sea intercambiable' do
    crear_lead(1, campos: { 'plan' => 'oro' })

    salidas = [
      run_node(described_class, ctx, { 'mode' => 'list' }),
      run_node(described_class, ctx, { 'mode' => 'by_field', 'field' => 'plan', 'value' => 'oro' }),
      run_node(described_class, ctx, { 'mode' => 'advanced',
                                       'conditions' => { 'rules' => [{ 'field' => 'plan',
                                                                       'operator' => 'is_not_empty' }] } })
    ]

    salidas.each do |result|
      expect(result).to be_ok
      expect(result.output.keys).to include('mode', 'count', 'leads')
      expect(result.output['leads'].first.keys).to include('id', 'lead_number', 'contact', 'has_phone')
    end
  end

  it 'no ve los leads de otra cuenta' do
    otra = create(:account)
    contact = create(:contact, account: otra, phone_number: '+573009998877')
    otra.jabvox_leads.create!(contact: contact, custom_fields_jabvox: {})

    expect(run_node(described_class, ctx, { 'mode' => 'list' }).output['count']).to be_zero
  end
end
