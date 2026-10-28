# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::ContactCompanyConditionNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:company) { create(:company, account: account) }
  let(:other_company) { create(:company, account: account) }
  let(:contact) { create(:contact, account: account, email: nil, identifier: 'c1') }
  let(:ctx) { build_ctx(account) }

  before { account.enable_features!('companies') }

  it 'sale por "true" cuando la empresa del contacto coincide (equals)' do
    contact.update!(company: company)
    result = run_node(described_class, ctx,
                      { 'contactId' => contact.id, 'operator' => 'equals', 'companyId' => company.id })
    expect(result).to be_ok
    expect(result.output_port).to eq('true')
  end

  it 'sale por "false" cuando la empresa es otra (equals)' do
    contact.update!(company: other_company)
    result = run_node(described_class, ctx,
                      { 'contactId' => contact.id, 'operator' => 'equals', 'companyId' => company.id })
    expect(result.output_port).to eq('false')
  end

  it 'operador "tiene empresa" (is_not_empty) ignora la empresa seleccionada' do
    contact.update!(company: company)
    result = run_node(described_class, ctx, { 'contactId' => contact.id, 'operator' => 'is_not_empty' })
    expect(result.output_port).to eq('true')
  end

  it 'operador "no tiene empresa" (is_empty) sale por true si no tiene' do
    result = run_node(described_class, ctx, { 'contactId' => contact.id, 'operator' => 'is_empty' })
    expect(result.output_port).to eq('true')
  end

  it 'no ve contactos de otra cuenta' do
    ajeno = create(:contact, account: create(:account), identifier: 'x')
    expect(run_node(described_class, ctx, { 'contactId' => ajeno.id, 'operator' => 'is_empty' }).error)
      .to match(/no existe en esta cuenta/)
  end
end
