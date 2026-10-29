# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.contact.find — búsqueda por CRITERIO seleccionable. Verifica que cada
# criterio resuelve bien, que la salida trae la ficha completa (atributos y
# empresa) y que el `q` heredado sigue funcionando.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::ContactFindNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  it 'busca por nombre (criterio texto) y enriquece la salida' do
    create(:contact, account: account, name: 'José Ñandú', custom_attributes: { 'origen' => 'web' })
    create(:contact, account: account, name: 'Otro')

    result = run_node(described_class, ctx,
                      { 'field' => 'name', 'operator' => 'contains', 'value' => 'ñandú' })

    expect(result).to be_ok
    expect(result.output['count']).to eq(1)
    contact = result.output['contacts'].first
    expect(contact).to include('name' => 'José Ñandú', 'contactId' => kind_of(Integer))
    expect(contact['custom_attributes']).to eq('origen' => 'web')
    expect(contact).to have_key('company')
  end

  it 'busca por etiqueta' do
    con = create(:contact, account: account, name: 'VIP')
    con.update!(label_list: ['vip'])
    create(:contact, account: account, name: 'Sin etiqueta')

    result = run_node(described_class, ctx, { 'field' => 'label', 'operator' => 'in', 'value' => 'vip' })

    expect(result.output['count']).to eq(1)
    expect(result.output['contacts'].first['name']).to eq('VIP')
  end

  it 'busca por empresa cuando el módulo de empresas está activo' do
    # enable_features! persiste: el nodo re-lee la cuenta de BD (Account.find) y
    # debe ver la feature activa para incluir la empresa en la salida.
    account.enable_features!('companies')
    company = account.companies.create!(name: 'ACME')
    create(:contact, account: account, name: 'De ACME', company: company)
    create(:contact, account: account, name: 'Sin empresa')

    result = run_node(described_class, ctx,
                      { 'field' => 'company', 'operator' => 'in', 'value' => company.id.to_s })

    expect(result.output['count']).to eq(1)
    expect(result.output['contacts'].first['company']).to include('id' => company.id, 'name' => 'ACME')
  end

  it 'busca por atributo personalizado (custom:)' do
    create(:contact, account: account, name: 'Con atributo', custom_attributes: { 'plan' => 'oro' })
    create(:contact, account: account, name: 'Otro plan', custom_attributes: { 'plan' => 'plata' })

    result = run_node(described_class, ctx,
                      { 'field' => 'custom:plan', 'operator' => 'equals', 'value' => 'oro' })

    expect(result.output['count']).to eq(1)
    expect(result.output['contacts'].first['name']).to eq('Con atributo')
  end

  it 'operador vacío/no vacío no exige valor' do
    create(:contact, account: account, name: 'Con email', email: 'a@b.co')
    create(:contact, account: account, name: 'Sin email', email: nil)

    result = run_node(described_class, ctx, { 'field' => 'email', 'operator' => 'not_empty' })

    expect(result.output['contacts'].map { |c| c['name'] }).to include('Con email')
    expect(result.output['contacts'].map { |c| c['name'] }).not_to include('Sin email')
  end

  it 'mantiene compatibilidad con el `q` heredado (OR fijo)' do
    create(:contact, account: account, name: 'Buscable', email: 'hit@x.co')
    create(:contact, account: account, name: 'No')

    result = run_node(described_class, ctx, { 'q' => 'Buscable' })

    expect(result.output['count']).to eq(1)
    expect(result.output['contacts'].first['name']).to eq('Buscable')
  end

  it 'exige un valor cuando el criterio lo necesita' do
    expect(run_node(described_class, ctx, { 'field' => 'name', 'operator' => 'contains', 'value' => '' }).error)
      .to match(/necesita un valor/)
  end
end
