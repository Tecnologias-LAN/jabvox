# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Nodos de ETIQUETAS. Cubren los dos fallos que ya se sufrieron en producción:
# la carrera al etiquetar y la etiqueta inexistente que se aplicaba igual.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::LabelAddNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end
  let(:ctx) { build_ctx(account) }

  before { create(:label, account: account, title: 'seguimiento') }

  describe Jabvox::Flows::Nodes::Jabvox::LabelAddNode do
    it 'añade la etiqueta a la conversación' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'labels' => ['seguimiento'] })

      expect(result).to be_ok
      expect(conversation.reload.label_list).to include('seguimiento')
    end

    it 'CONSERVA las etiquetas que ya tenía: la escritura fija el set completo' do
      create(:label, account: account, title: 'vip')
      conversation.update!(label_list: ['vip'])

      run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'labels' => ['seguimiento'] })

      expect(conversation.reload.label_list).to match_array(%w[vip seguimiento])
    end

    it 'RECHAZA una etiqueta que no existe en el catálogo de la cuenta' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'labels' => ['seguimeinto'] })

      expect(result).not_to be_ok
      expect(result.error).to match(/no existe en esta cuenta/)
      # Y no se aplicó: `label_list=` la habría creado al vuelo.
      expect(conversation.reload.label_list).to be_empty
    end

    it 'falla claro cuando la conversación ya no existe' do
      result = run_node(described_class, ctx, { 'conversationId' => 999_999, 'labels' => ['seguimiento'] })

      expect(result.error).to match(/no existe en esta cuenta/)
    end

    it 'falla cuando no se eligió ninguna etiqueta' do
      result = run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'labels' => [] })

      expect(result.error).to match(/al menos una etiqueta/)
    end

    it 'no alcanza una conversación de OTRA cuenta' do
      ajena = create(:conversation, account: create(:account))

      result = run_node(described_class, ctx, { 'conversationId' => ajena.display_id, 'labels' => ['seguimiento'] })

      expect(result).not_to be_ok
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::LabelRemoveNode do
    it 'quita solo SU etiqueta y deja las demás' do
      create(:label, account: account, title: 'vip')
      conversation.update!(label_list: %w[vip seguimiento])

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'labels' => ['seguimiento'] })

      expect(result).to be_ok
      expect(conversation.reload.label_list).to eq(['vip'])
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ContactAddLabelsNode do
    it 'etiqueta el CONTACTO, que es un set separado del de la conversación' do
      result = run_node(described_class, ctx, { 'contactId' => contact.id, 'labels' => ['seguimiento'] })

      expect(result).to be_ok
      expect(contact.reload.label_list).to include('seguimiento')
      expect(conversation.reload.label_list).to be_empty
    end
  end

  describe Jabvox::Flows::Nodes::LabelWriter do
    it 'normaliza a minúsculas: el catálogo guarda los títulos en minúscula' do
      expect(described_class.normalize(['Seguimiento', ' VIP '])).to eq(%w[seguimiento vip])
    end

    it 'no se pisa a sí mismo con escrituras encadenadas sobre el mismo registro' do
      create(:label, account: account, title: 'alfa')
      create(:label, account: account, title: 'beta')

      described_class.apply(conversation, ['alfa'], :add)
      final = described_class.apply(conversation, ['beta'], :add)

      expect(final).to match_array(%w[alfa beta])
    end
  end
end
