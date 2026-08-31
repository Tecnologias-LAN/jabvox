# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Mensaje en conversación y nota en contacto.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::ConversationSendMessageNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:ctx) { build_ctx(account) }

  describe Jabvox::Flows::Nodes::Jabvox::ConversationSendMessageNode do
    it 'publica un mensaje saliente en la conversación' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'content' => 'Hola' })

      expect(result).to be_ok
      expect(result.output['private']).to be(false)
      expect(conversation.messages.last.content).to eq('Hola')
    end

    it 'con private=true deja una NOTA PRIVADA que no sale al cliente' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'content' => 'Interno', 'private' => true })

      expect(result.output['private']).to be(true)
      expect(conversation.messages.last).to be_private
    end

    it 'interpola las plantillas del contenido' do
      ctx = build_ctx(account, vars: { 'nombre' => 'Ana' })

      run_node(described_class, ctx,
               { 'conversationId' => conversation.display_id, 'content' => 'Hola {{vars.nombre}}' })

      expect(conversation.messages.last.content).to eq('Hola Ana')
    end

    it 'rechaza un mensaje vacío' do
      result = run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'content' => '   ' })

      expect(result.error).to match(/no puede estar vacío/)
    end

    it 'falla claro si la conversación fue borrada' do
      result = run_node(described_class, ctx, { 'conversationId' => 999_999, 'content' => 'Hola' })

      expect(result.error).to match(/no existe en esta cuenta/)
    end

    it 'explica QUÉ campo falta cuando el id llega vacío' do
      result = run_node(described_class, ctx, { 'conversationId' => '', 'content' => 'Hola' })

      expect(result.error).to match(/Falta el ID de la conversación/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::NoteCreateNode do
    it 'crea la nota en la ficha del contacto' do
      result = run_node(described_class, ctx, { 'contactId' => contact.id, 'content' => 'Llamar mañana' })

      expect(result).to be_ok
      expect(contact.notes.last.content).to eq('Llamar mañana')
    end

    it 'rechaza una nota vacía' do
      expect(run_node(described_class, ctx, { 'contactId' => contact.id, 'content' => '' }).error)
        .to match(/no puede estar vacía/)
    end

    it 'no alcanza un contacto de otra cuenta' do
      ajeno = create(:contact, account: create(:account))

      result = run_node(described_class, ctx, { 'contactId' => ajeno.id, 'content' => 'x' })

      expect(result.error).to match(/no existe en esta cuenta/)
    end
  end
end
