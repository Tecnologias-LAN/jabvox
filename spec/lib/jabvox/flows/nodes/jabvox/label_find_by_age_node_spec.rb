# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.label.find_by_age — es el nodo que abre las cadenas de seguimiento en
# producción, así que se cubren sus filtros y sus casos de "0 resultados".
RSpec.describe Jabvox::Flows::Nodes::Jabvox::LabelFindByAgeNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  # Conversación etiquetada hace `hours` horas, con teléfono opcional.
  # Contador de teléfonos: el número de contacto es ÚNICO por cuenta.
  let(:secuencia) { [0] }
  let(:inbox) { create(:inbox, account: account) }
  let(:ctx) { build_ctx(account) }

  before { create(:label, account: account, title: 'seguimiento') }

  def etiquetar(hours:, phone: :auto, status: :open)
    secuencia[0] += 1
    number = phone == :auto ? format('+5730011122%<n>02d', n: secuencia[0]) : phone
    contact = create(:contact, account: account, phone_number: number)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: status)
    conversation.update!(label_list: ['seguimiento'])
    JabvoxConversationLabelLog.open.find_by(conversation_id: conversation.id, label_jabvox: 'seguimiento')
                              .update!(applied_at_jabvox: hours.hours.ago)
    conversation
  end

  it 'declara itemsPath para que {{node.<id>.items}} resuelva la colección' do
    expect(described_class.node_items_path).to eq('conversations')
  end

  it 'devuelve las conversaciones que superan las horas mínimas' do
    vieja = etiquetar(hours: 30)
    etiquetar(hours: 2)

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24 })

    expect(result).to be_ok
    expect(result.output['count']).to eq(1)
    expect(result.output['conversations'].first['display_id']).to eq(vieja.display_id)
  end

  it 'con minHours VACÍO usa 24 h, no 0 h' do
    etiquetar(hours: 2)

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => '' })

    expect(result.output['minHours']).to eq(24)
    expect(result.output['count']).to be_zero
  end

  it 'devuelve una colección VACÍA sin fallar cuando no hay nada que hacer' do
    result = run_node(described_class, ctx, { 'label' => 'seguimiento' })

    expect(result).to be_ok
    expect(result.output['conversations']).to eq([])
    expect(result.output['count']).to be_zero
  end

  it 'descarta a quien RESPONDIÓ después de ponerse la etiqueta' do
    conversation = etiquetar(hours: 30)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, created_at: 1.hour.ago)

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24 })

    expect(result.output['count']).to be_zero
    # Pero se contabiliza como revisada: un 0 sin explicación es inservible.
    expect(result.output['checked']).to eq(1)
  end

  it 'informa de los contactos SIN teléfono y los filtra si se pide' do
    etiquetar(hours: 30, phone: nil)

    sin_filtro = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24 })
    con_filtro = run_node(described_class, ctx,
                          { 'label' => 'seguimiento', 'minHours' => 24, 'onlyWithPhone' => true })

    expect(sin_filtro.output['count']).to eq(1)
    expect(sin_filtro.output['without_phone']).to eq(1)
    expect(sin_filtro.output['conversations'].first['has_phone']).to be(false)
    expect(con_filtro.output['count']).to be_zero
  end

  it 'filtra por estado de la conversación' do
    etiquetar(hours: 30, status: :resolved)

    result = run_node(described_class, ctx,
                      { 'label' => 'seguimiento', 'minHours' => 24, 'statuses' => ['open'] })

    expect(result.output['count']).to be_zero
  end

  it 'avisa cuando la consulta llegó al tope en vez de callar' do
    2.times { etiquetar(hours: 30) }

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24, 'limit' => 2 })

    expect(result.output['truncated']).to be(true)
    expect(result.output['aviso']).to match(/tope de 2 conversaciones/)
  end

  it 'IGNORA los logs cuya conversación ya no existe, en vez de romper' do
    conversation = etiquetar(hours: 30)
    log = JabvoxConversationLabelLog.open.find_by(conversation_id: conversation.id)
    conversation.destroy!
    # rubocop:disable Rails/SkipsModelValidations -- se simula un log huérfano
    log.update_columns(conversation_id: 999_999, removed_at_jabvox: nil)
    # rubocop:enable Rails/SkipsModelValidations

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24 })

    expect(result).to be_ok
    expect(result.output['count']).to be_zero
  end

  it 'falla claro si no se eligió etiqueta' do
    expect(run_node(described_class, ctx, { 'label' => '' }).error).to match(/Falta la "Etiqueta"/)
  end

  it 'rechaza unas horas mínimas negativas' do
    expect(run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => -3 }).error)
      .to match(/número de horas >= 0/)
  end

  it 'no ve las conversaciones de OTRA cuenta' do
    otra = create(:account)
    create(:label, account: otra, title: 'seguimiento')
    conversation = create(:conversation, account: otra, inbox: create(:inbox, account: otra))
    conversation.update!(label_list: ['seguimiento'])
    JabvoxConversationLabelLog.open.find_by(conversation_id: conversation.id)
                              .update!(applied_at_jabvox: 30.hours.ago)

    result = run_node(described_class, ctx, { 'label' => 'seguimiento', 'minHours' => 24 })

    expect(result.output['count']).to be_zero
  end
end
