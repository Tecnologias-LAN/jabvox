# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::ContactCreateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  describe described_class do
    it 'crea el contacto y expone contactId para encadenar' do
      result = run_node(described_class, ctx,
                        { 'name' => 'Ana', 'phone_number' => '+573001112233', 'email' => 'ana@ej.com' })

      expect(result).to be_ok
      expect(result.output['contactId']).to eq(account.contacts.last.id)
      expect(account.contacts.last.name).to eq('Ana')
    end

    it 'guarda los atributos personalizados descartando las claves vacías' do
      result = run_node(described_class, ctx,
                        { 'name' => 'Ana', 'custom_attributes' => { 'ciudad' => 'Bogotá', '' => 'x', 'z' => '' } })

      expect(result.output['custom_attributes']).to eq('ciudad' => 'Bogotá')
    end

    it 'rechaza un contacto sin ningún dato' do
      expect(run_node(described_class, ctx, { 'name' => '', 'email' => '' }).error)
        .to match(/al menos un nombre/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ContactUpdateNode do
    let(:contact) { create(:contact, account: account, name: 'Ana', email: 'ana@ej.com') }

    it 'actualiza SOLO lo configurado y no borra lo demás' do
      result = run_node(described_class, ctx, { 'contactId' => contact.id, 'name' => 'Ana María' })

      expect(result).to be_ok
      expect(contact.reload.name).to eq('Ana María')
      # El email no se configuró: sigue intacto.
      expect(contact.email).to eq('ana@ej.com')
    end

    it 'FUSIONA los atributos personalizados en vez de reemplazarlos' do
      contact.update!(custom_attributes: { 'ciudad' => 'Bogotá' })

      run_node(described_class, ctx,
               { 'contactId' => contact.id, 'custom_attributes' => { 'plan' => 'oro' } })

      expect(contact.reload.custom_attributes).to eq('ciudad' => 'Bogotá', 'plan' => 'oro')
    end

    it 'falla si no se configuró nada que actualizar' do
      expect(run_node(described_class, ctx, { 'contactId' => contact.id }).error)
        .to match(/ningún campo que actualizar/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ContactSetCustomAttrsNode do
    let(:contact) { create(:contact, account: account, custom_attributes: { 'ciudad' => 'Bogotá' }) }

    it 'fija un atributo sin tocar los otros' do
      result = run_node(described_class, ctx,
                        { 'contactId' => contact.id, 'attribute' => 'plan', 'value' => 'oro' })

      expect(result).to be_ok
      expect(contact.reload.custom_attributes).to eq('ciudad' => 'Bogotá', 'plan' => 'oro')
    end

    it 'exige elegir el atributo' do
      expect(run_node(described_class, ctx, { 'contactId' => contact.id, 'attribute' => '' }).error)
        .to match(/Elige el atributo/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ContactFindNode do
    it 'declara itemsPath para que el bucle reciba la colección' do
      expect(described_class.node_items_path).to eq('contacts')
    end

    it 'encuentra por nombre, email o teléfono' do
      create(:contact, account: account, name: 'Ana', phone_number: '+573001112233')
      create(:contact, account: account, name: 'Luis', phone_number: '+573004445566')

      result = run_node(described_class, ctx, { 'q' => 'Ana' })

      expect(result.output['count']).to eq(1)
      expect(result.output['contacts'].first['name']).to eq('Ana')
    end

    it 'devuelve una colección VACÍA sin fallar' do
      result = run_node(described_class, ctx, { 'q' => 'nadie' })

      expect(result).to be_ok
      expect(result.output['contacts']).to eq([])
    end

    it 'avisa cuando llegó al tope en vez de callar' do
      2.times { |i| create(:contact, account: account, name: "Cliente #{i}") }

      result = run_node(described_class, ctx, { 'q' => 'Cliente', 'limit' => 2 })

      expect(result.output['truncated']).to be(true)
    end

    it 'no ve los contactos de otra cuenta' do
      create(:contact, account: create(:account), name: 'Ajeno')

      expect(run_node(described_class, ctx, { 'q' => 'Ajeno' }).output['count']).to be_zero
    end

    it 'exige el texto a buscar' do
      expect(run_node(described_class, ctx, { 'q' => '  ' }).error).to match(/Escribe el texto a buscar/)
    end
  end
end
