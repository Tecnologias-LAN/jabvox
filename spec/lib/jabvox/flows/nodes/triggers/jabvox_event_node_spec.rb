# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::Nodes::Triggers::JabvoxEventNode do
  def node(params)
    Jabvox::Flows::Engine::Graph::Node.new(id: 't', type: 'trigger.jabvox_event', params: params, data: {})
  end

  it 'casa el evento pedido y descarta los demás' do
    config = node('event' => 'conversation_created')

    expect(described_class.matches?(config, { 'event' => 'conversation_created' })).to be(true)
    expect(described_class.matches?(config, { 'event' => 'message_created' })).to be(false)
  end

  it 'con «*» casa cualquier evento' do
    expect(described_class.matches?(node('event' => '*'), { 'event' => 'lo_que_sea' })).to be(true)
  end

  it 'filtra por bandeja e IGNORA los eventos que no la llevan' do
    config = node('event' => '*', 'inboxId' => '7')

    expect(described_class.matches?(config, { 'event' => 'x', 'inbox_id' => 7 })).to be(true)
    expect(described_class.matches?(config, { 'event' => 'x', 'inbox_id' => 9 })).to be(false)
    # Un contacto creado no lleva bandeja: no se puede afirmar que sea de la suya.
    expect(described_class.matches?(config, { 'event' => 'contact_created' })).to be(false)
  end

  it 'exige TODAS las condiciones del filtro, con rutas con punto' do
    config = node('event' => '*', 'filterJson' => { 'status' => 'open', 'meta.sender.email' => 'a@b.com' })
    sender = { 'meta' => { 'sender' => { 'email' => 'a@b.com' } } }

    expect(described_class.matches?(config, sender.merge('status' => 'open'))).to be(true)
    expect(described_class.matches?(config, sender.merge('status' => 'resolved'))).to be(false)
  end

  it 'admite una lista de valores como OR' do
    config = node('event' => '*', 'filterJson' => { 'status' => %w[open pending] })

    expect(described_class.matches?(config, { 'status' => 'pending' })).to be(true)
    expect(described_class.matches?(config, { 'status' => 'resolved' })).to be(false)
  end

  it 'compara por texto: los ids llegan number en unos eventos y string en otros' do
    config = node('event' => '*', 'filterJson' => { 'id' => '42' })

    expect(described_class.matches?(config, { 'id' => 42 })).to be(true)
  end

  it 'IGNORA un filtro corrupto en vez de bloquear el disparo' do
    config = node('event' => '*', 'filterJson' => 'esto no es json')

    expect(described_class.matches?(config, { 'event' => 'x' })).to be(true)
  end

  it 'acepta el filtro como JSON en texto' do
    config = node('event' => '*', 'filterJson' => '{"status":"open"}')

    expect(described_class.matches?(config, { 'status' => 'open' })).to be(true)
    expect(described_class.matches?(config, { 'status' => 'resolved' })).to be(false)
  end
end
