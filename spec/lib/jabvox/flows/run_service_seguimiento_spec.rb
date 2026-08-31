# frozen_string_literal: true

require 'rails_helper'

# Recorrido COMPLETO del flujo que hoy corre en producción: buscar las
# conversaciones que llevan N horas con una etiqueta, recorrerlas con el bucle y
# actuar sobre cada una. Es la prueba de que la cadena entera encaja: itemsPath,
# `{{item.*}}` y los nodos de acción con acceso directo a los modelos.
RSpec.describe Jabvox::Flows::RunService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:flow) { JabvoxFlow.create!(account: account, name: 'Seguimiento 24h') }

  let(:graph) do
    { 'nodes' => [
        { 'id' => 'inicio', 'type' => 'trigger.schedule' },
        { 'id' => 'buscar', 'type' => 'jabvox.label.find_by_age',
          'params' => { 'label' => 'seguimiento', 'minHours' => 24, 'onlyWithPhone' => true } },
        { 'id' => 'bucle', 'type' => 'logic.loop',
          'params' => { 'items' => '{{node.buscar.items}}' } },
        { 'id' => 'nota', 'type' => 'jabvox.conversation.send_message',
          'params' => { 'conversationId' => '{{item.display_id}}',
                        'content' => 'Sin respuesta tras {{item.hours_applied}} h.', 'private' => true } },
        { 'id' => 'marcar', 'type' => 'jabvox.label.add',
          'params' => { 'conversationId' => '{{item.display_id}}', 'labels' => ['avisado'] } }
      ],
      'edges' => [
        { 'id' => 'e1', 'source' => 'inicio', 'target' => 'buscar' },
        { 'id' => 'e2', 'source' => 'buscar', 'target' => 'bucle' },
        { 'id' => 'e3', 'source' => 'bucle', 'target' => 'nota', 'sourceHandle' => 'loop' },
        { 'id' => 'e4', 'source' => 'nota', 'target' => 'marcar' }
      ] }
  end

  def etiquetar(numero)
    contact = create(:contact, account: account, phone_number: "+57300111223#{numero}")
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    conversation.update!(label_list: ['seguimiento'])
    JabvoxConversationLabelLog.open.find_by(conversation_id: conversation.id, label_jabvox: 'seguimiento')
                              .update!(applied_at_jabvox: 30.hours.ago)
    conversation
  end

  def ejecutar
    version = JabvoxFlowVersion.create!(flow: flow, version: 1, graph: graph)
    flow.update!(current_version: version)
    run = JabvoxFlowRun.create!(account: account, flow: flow, version: version, trigger: {})
    [described_class.new(run).call(trigger_type: 'trigger.schedule'), run]
  end

  before do
    create(:label, account: account, title: 'seguimiento')
    create(:label, account: account, title: 'avisado')
  end

  it 'recorre las conversaciones encontradas y actúa sobre cada una' do
    conversaciones = [etiquetar(1), etiquetar(2)]

    status, run = ejecutar

    expect(status).to eq(:success)
    expect(run.reload).to be_success
    conversaciones.each do |conversation|
      expect(conversation.reload.label_list).to include('avisado')
      expect(conversation.messages.last).to be_private
      expect(conversation.messages.last.content).to match(/Sin respuesta tras 30/)
    end
  end

  it 'deja traza de un paso por conversación, sellado con su iteración' do
    2.times { |i| etiquetar(i + 1) }

    _status, run = ejecutar

    expect(run.steps.where(node_id: 'marcar').count).to eq(2)
    expect(run.steps.where(node_id: 'marcar').map { |s| s.loop_context['posicion'] }).to eq([1, 2])
  end

  it 'termina en verde sin hacer nada cuando no hay conversaciones que avisar' do
    status, run = ejecutar

    expect(status).to eq(:success)
    # El bucle no dio ninguna vuelta: cero es un resultado legítimo.
    expect(run.steps.where(node_id: 'marcar').count).to be_zero
    expect(run.steps.find_by(node_id: 'buscar').output['count']).to be_zero
  end

  it 'salta la conversación cuyo contacto no tiene teléfono' do
    etiquetar(1)
    sin_telefono = create(:contact, account: account, phone_number: nil)
    conversation = create(:conversation, account: account, inbox: inbox, contact: sin_telefono)
    conversation.update!(label_list: ['seguimiento'])
    JabvoxConversationLabelLog.open.find_by(conversation_id: conversation.id)
                              .update!(applied_at_jabvox: 30.hours.ago)

    _status, run = ejecutar

    expect(run.steps.where(node_id: 'marcar').count).to eq(1)
    expect(conversation.reload.label_list).not_to include('avisado')
  end
end
