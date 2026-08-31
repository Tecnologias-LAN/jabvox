# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# Familia de conversación: crear, asignar (agente/equipo) y cambiar de estado.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::ConversationCreateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+573001112233') }
  let(:ctx) { build_ctx(account) }

  describe described_class do
    it 'crea la conversación y expone conversationId = display_id para encadenar' do
      result = run_node(described_class, ctx, { 'inboxId' => inbox.id, 'contactId' => contact.id })

      expect(result).to be_ok
      conversation = account.conversations.last
      expect(result.output['conversationId']).to eq(conversation.display_id)
      expect(result.output['internal_id']).to eq(conversation.id)
      expect(conversation.contact_inbox).to be_present
    end

    it 'publica el mensaje inicial cuando se configura' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'message' => 'Hola' })

      conversation = account.conversations.last
      expect(conversation.messages.last.content).to eq('Hola')
      expect(conversation.messages.last).not_to be_private
      expect(result.output['message_id']).to eq(conversation.messages.last.id)
    end

    it 'no crea mensaje si el texto inicial está en blanco' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'message' => '   ' })

      expect(result.output['message_id']).to be_nil
      expect(account.conversations.last.messages).to be_empty
    end

    it 'nace con el estado, el agente y el equipo configurados' do
      agent = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      team.add_members([agent.id])

      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'status' => 'pending',
                          'assigneeId' => agent.id, 'teamId' => team.id })

      expect(result.output['status']).to eq('pending')
      expect(result.output['assignee_id']).to eq(agent.id)
      expect(result.output['team_id']).to eq(team.id)
    end

    it 'usa "open" cuando el estado llega vacío (no lo trata como valor)' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'status' => '' })

      expect(result.output['status']).to eq('open')
    end

    it 'rechaza un estado fuera del enum en vez de reventar' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'status' => 'cerrada' })

      expect(result.error).to match(/no es un estado válido/)
    end

    it 'respeta el sourceId configurado' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'sourceId' => 'abc-123' })

      expect(result.output['source_id']).to eq('abc-123')
    end

    it 'no crea nada si el agente no existe en la cuenta' do
      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'assigneeId' => 999_999 })

      expect(result.error).to match(/El agente 999999 no existe en esta cuenta/)
      expect(account.conversations).to be_empty
    end

    it 'no crea nada si el equipo es de OTRA cuenta' do
      other_team = create(:team, account: create(:account))

      result = run_node(described_class, ctx,
                        { 'inboxId' => inbox.id, 'contactId' => contact.id, 'teamId' => other_team.id })

      expect(result.error).to match(/no existe en esta cuenta/)
      expect(account.conversations).to be_empty
    end

    it 'falla claro si la bandeja es de otra cuenta' do
      other_inbox = create(:inbox, account: create(:account))

      result = run_node(described_class, ctx, { 'inboxId' => other_inbox.id, 'contactId' => contact.id })

      expect(result.error).to match(/La bandeja #{other_inbox.id} no existe en esta cuenta/)
    end

    it 'explica QUÉ campo falta cuando la bandeja llega vacía' do
      expect(run_node(described_class, ctx, { 'inboxId' => '', 'contactId' => contact.id }).error)
        .to match(/Falta la "Bandeja"/)
    end

    it 'explica QUÉ campo falta cuando el contacto llega vacío' do
      expect(run_node(described_class, ctx, { 'inboxId' => inbox.id, 'contactId' => '' }).error)
        .to match(/Falta el ID interno del contacto/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ConversationAssignNode do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:team) { create(:team, account: account) }

    it 'asigna solo el agente' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'assigneeId' => agent.id })

      expect(result).to be_ok
      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(result.output['assignee_name']).to eq(agent.name)
    end

    it 'asigna solo el equipo' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'teamId' => team.id })

      expect(conversation.reload.team_id).to eq(team.id)
      expect(result.output['team_id']).to eq(team.id)
    end

    it 'asigna AGENTE Y EQUIPO en la misma llamada (el equipo ya no se ignora)' do
      team.add_members([agent.id])

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id,
                          'assigneeId' => agent.id, 'teamId' => team.id })

      expect(result).to be_ok
      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(conversation.team_id).to eq(team.id)
    end

    it 'avisa (y no cambia nada) si el agente no es miembro del equipo pedido' do
      team.update!(allow_auto_assign: false)

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id,
                          'assigneeId' => agent.id, 'teamId' => team.id })

      expect(result.error).to match(/NO es miembro del equipo/)
      expect(conversation.reload.team_id).to be_nil
      expect(conversation.assignee_id).to be_nil
    end

    it 'un agente inexistente NO desasigna: falla y deja la asignación previa' do
      previous = create(:user, account: account, role: :agent)
      conversation.update!(assignee_id: previous.id)

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'assigneeId' => 999_999 })

      expect(result.error).to match(/El agente 999999 no existe/)
      expect(conversation.reload.assignee_id).to eq(previous.id)
    end

    it 'un equipo de otra cuenta NO desasigna: falla y deja el equipo previo' do
      conversation.update!(team_id: team.id)
      other_team = create(:team, account: create(:account))

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'teamId' => other_team.id })

      expect(result.error).to match(/no existe en esta cuenta/)
      expect(conversation.reload.team_id).to eq(team.id)
    end

    it 'exige elegir al menos un destinatario' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'assigneeId' => '', 'teamId' => '' })

      expect(result.error).to match(/al menos un destinatario/)
    end

    it 'falla claro si la conversación no existe' do
      expect(run_node(described_class, ctx, { 'conversationId' => 999_999, 'assigneeId' => agent.id }).error)
        .to match(/no existe en esta cuenta/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::TeamAssignNode do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:team) { create(:team, account: account) }

    it 'asigna el equipo' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'teamId' => team.id })

      expect(result).to be_ok
      expect(conversation.reload.team_id).to eq(team.id)
      expect(result.output['team_name']).to eq(team.name)
    end

    it 'declara en la salida si Rails quitó al agente por no ser del equipo' do
      agent = create(:user, account: account, role: :agent)
      conversation.update!(assignee_id: agent.id)
      team.update!(allow_auto_assign: false)

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'teamId' => team.id })

      expect(result.output['assignee_removed']).to be(true)
      expect(result.output['assignee_id']).to be_nil
    end

    it 'un equipo inexistente NO desasigna: falla y conserva el equipo previo' do
      conversation.update!(team_id: team.id)

      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'teamId' => 999_999 })

      expect(result.error).to match(/El equipo 999999 no existe en esta cuenta/)
      expect(conversation.reload.team_id).to eq(team.id)
    end

    it 'explica QUÉ campo falta cuando el equipo llega vacío' do
      expect(run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'teamId' => '' }).error)
        .to match(/Falta el "Equipo"/)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::ConversationToggleStatusNode do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'open') }

    it 'resuelve la conversación' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'status' => 'resolved' })

      expect(result).to be_ok
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'usa "resolved" cuando el estado llega vacío' do
      run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'status' => '' })

      expect(conversation.reload.status).to eq('resolved')
    end

    it 'pospone con una FECHA LEGIBLE sin caer en 1970' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'status' => 'snoozed',
                          'snoozedUntil' => '2030-08-01 09:00' })

      expect(result).to be_ok
      expect(conversation.reload.snoozed_until.year).to eq(2030)
    end

    it 'pospone también con un timestamp Unix en segundos' do
      moment = 1_912_000_000

      run_node(described_class, ctx,
               { 'conversationId' => conversation.display_id, 'status' => 'snoozed',
                 'snoozedUntil' => moment.to_s })

      expect(conversation.reload.snoozed_until.to_i).to eq(moment)
    end

    it 'pospone indefinidamente si la fecha llega vacía' do
      run_node(described_class, ctx,
               { 'conversationId' => conversation.display_id, 'status' => 'snoozed', 'snoozedUntil' => '' })

      expect(conversation.reload.status).to eq('snoozed')
      expect(conversation.snoozed_until).to be_nil
    end

    it 'acepta también una fecha ISO con zona horaria' do
      run_node(described_class, ctx,
               { 'conversationId' => conversation.display_id, 'status' => 'snoozed',
                 'snoozedUntil' => '2030-08-01T09:00:00Z' })

      expect(conversation.reload.snoozed_until.utc.hour).to eq(9)
    end

    it 'FALLA con un texto libre en vez de inventarse una fecha' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'status' => 'snoozed',
                          'snoozedUntil' => 'el martes que viene' })

      expect(result.error).to match(/No se entiende la fecha/)
      expect(conversation.reload.status).to eq('open')
    end

    it 'FALLA con una fecha imposible en vez de guardar 1970' do
      result = run_node(described_class, ctx,
                        { 'conversationId' => conversation.display_id, 'status' => 'snoozed',
                          'snoozedUntil' => '2030-13-45' })

      expect(result.error).to match(/No se entiende la fecha/)
      expect(conversation.reload.snoozed_until).to be_nil
    end

    it 'limpia snoozed_until al salir de "pospuesta"' do
      conversation.update!(status: 'snoozed', snoozed_until: 1.day.from_now)

      run_node(described_class, ctx, { 'conversationId' => conversation.display_id, 'status' => 'open' })

      expect(conversation.reload.snoozed_until).to be_nil
    end

    it 'rechaza un estado fuera del enum' do
      expect(run_node(described_class, ctx,
                      { 'conversationId' => conversation.display_id, 'status' => 'cerrada' }).error)
        .to match(/no es un estado válido/)
    end

    it 'falla claro si la conversación es de otra cuenta' do
      other = create(:conversation, account: create(:account))

      expect(run_node(described_class, ctx,
                      { 'conversationId' => other.display_id, 'status' => 'resolved' }).error)
        .to match(/no existe en esta cuenta/)
    end
  end
end
