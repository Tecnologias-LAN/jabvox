# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Tipificaciones y estados de gestión.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::TypificationCreateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  describe described_class do
    it 'crea la tipificación activa por defecto' do
      result = run_node(described_class, ctx, { 'name' => 'Venta cerrada' })

      expect(result).to be_ok
      expect(result.output['created']).to be(true)
      expect(result.output['is_active']).to be(true)
      expect(account.jabvox_typifications.last.name).to eq('Venta cerrada')
    end

    it 'guarda la descripción y permite crearla inactiva' do
      result = run_node(described_class, ctx,
                        { 'name' => 'No contesta', 'description' => 'Sin respuesta', 'is_active' => false })

      expect(result.output['description']).to eq('Sin respuesta')
      expect(result.output['is_active']).to be(false)
    end

    it 'es IDEMPOTENTE: con un nombre ya existente devuelve created=false sin pisarla' do
      existing = account.jabvox_typifications.create!(name: 'Venta cerrada', description: 'Original')

      result = run_node(described_class, ctx, { 'name' => 'Venta cerrada', 'description' => 'Otra' })

      expect(result).to be_ok
      expect(result.output['created']).to be(false)
      expect(result.output['id']).to eq(existing.id)
      expect(existing.reload.description).to eq('Original')
    end

    it 'el nombre repetido en OTRA cuenta no bloquea la creación' do
      create(:account).jabvox_typifications.create!(name: 'Venta cerrada')

      result = run_node(described_class, ctx, { 'name' => 'Venta cerrada' })

      expect(result.output['created']).to be(true)
    end

    it 'exige el nombre' do
      expect(run_node(described_class, ctx, { 'name' => '   ' }).error).to match(/Falta el "Nombre"/)
    end

    it 'devuelve el motivo real cuando el modelo rechaza el nombre' do
      result = run_node(described_class, ctx, { 'name' => 'x' * 200 })

      expect(result.error).to match(/No se pudo crear la tipificación/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::StateSetManagementStateNode do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'registra el estado como NOTA PRIVADA con el atributo que lee Jabvox' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'state' => 'Interesado' })

      expect(result).to be_ok
      message = conversation.messages.last
      expect(message).to be_private
      expect(message.content_attributes['jabvox_management_state_name']).to eq('Interesado')
      expect(message.content).to eq('Estado de gestión: Interesado')
    end

    it 'usa la nota configurada cuando se escribe' do
      run_node(described_class, ctx,
               { 'conversationId' => conversation.display_id, 'state' => 'Interesado', 'note' => 'Pide llamada' })

      expect(conversation.messages.last.content).to eq('Pide llamada')
    end

    it 'copia la ficha del estado real de la cuenta (grupo, color, clasificación)' do
      state = account.jabvox_management_states.create!(name_jabvox: 'Interesado', state_group_jabvox: 'Llamada',
                                                       color_jabvox: '#00ff00', positivity_level_jabvox: 80)

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'state' => 'Interesado' })

      expect(result.output['known_state']).to be(true)
      expect(result.output['state_id']).to eq(state.id)
      attrs = conversation.messages.last.content_attributes
      expect(attrs['jabvox_management_state_group']).to eq('Llamada')
      expect(attrs['jabvox_management_positivity_level']).to eq(80)
    end

    it 'avisa con known_state=false si el estado no está en el catálogo de la cuenta' do
      create(:account).jabvox_management_states.create!(name_jabvox: 'Ajeno')

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'state' => 'Ajeno' })

      expect(result.output['known_state']).to be(false)
      expect(result.output['state_id']).to be_nil
    end

    it 'marca el origen para que la gestión no quede como "unknown" en los informes' do
      account.jabvox_management_states.create!(name_jabvox: 'Interesado')

      run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'state' => 'Interesado' })

      expect(conversation.messages.last.content_attributes['jabvox_call_source']).to eq('automation')
    end

    it 'exige el estado' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'state' => '  ' })

      expect(result.error).to match(/Falta el "Estado de gestión"/)
      expect(conversation.messages).to be_empty
    end

    it 'falla claro si la conversación no existe' do
      expect(run_node(described_class, ctx, { 'conversationId' => 999_999, 'state' => 'Interesado' }).error)
        .to match(/no existe en esta cuenta/)
    end
  end
end
