# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::Nodes::Triggers::WebhookNode do
  def node(params)
    Jabvox::Flows::Engine::Graph::Node.new(id: 't', type: 'trigger.webhook', params: params, data: {})
  end

  it 'solo acepta POST cuando no se configuran métodos' do
    config = node({})

    expect(described_class.method_allowed?(config, 'POST')).to be(true)
    expect(described_class.method_allowed?(config, 'GET')).to be(false)
  end

  it 'acepta los métodos configurados, sin importar la caja' do
    config = node('allowedMethods' => %w[GET PUT])

    expect(described_class.method_allowed?(config, 'get')).to be(true)
    expect(described_class.method_allowed?(config, 'POST')).to be(false)
  end

  it 'sin secreto configurado basta el token de la URL' do
    expect(described_class.secret_valid?(node({}), nil)).to be(true)
  end

  it 'con secreto configurado exige que coincida' do
    config = node('secret' => 'abc123')

    expect(described_class.secret_valid?(config, 'abc123')).to be(true)
    expect(described_class.secret_valid?(config, 'otro')).to be(false)
    expect(described_class.secret_valid?(config, nil)).to be(false)
  end
end
