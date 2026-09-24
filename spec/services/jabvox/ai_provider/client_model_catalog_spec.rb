# frozen_string_literal: true

require 'rails_helper'

# El catálogo debe distinguir el PROVEEDOR de cada modelo para poder elegir modelos sueltos
# ('gpt-4') agrupados por proveedor, en vez de tratar 'openai' como un bloque indivisible.
RSpec.describe Jabvox::AiProvider::Client do
  def client_returning(rows)
    adapter = Class.new do
      def initialize(rows) = @rows = rows

      def request(_method, path, **)
        return { status: 200, body: { 'data' => @rows }, body_text: '' } if path == '/model/info'

        { status: 404, body: {}, body_text: '' }
      end
    end.new(rows)
    Jabvox::AiProvider::Client.new(adapter: adapter)
  end

  it 'usa model_info.litellm_provider cuando está presente' do
    catalog = client_returning(
      [{ 'model_name' => 'gpt-4', 'model_info' => { 'litellm_provider' => 'openai' } }]
    ).model_catalog

    expect(catalog).to eq([{ name: 'gpt-4', provider: 'openai' }])
  end

  it 'cae al prefijo de litellm_params.model si no hay litellm_provider' do
    catalog = client_returning(
      [{ 'model_name' => 'sonnet', 'litellm_params' => { 'model' => 'anthropic/claude-sonnet-4' } }]
    ).model_catalog

    expect(catalog.first[:provider]).to eq('anthropic')
  end

  it 'usa el prefijo del propio nombre como último recurso' do
    catalog = client_returning([{ 'model_name' => 'groq/llama-3' }]).model_catalog

    expect(catalog.first[:provider]).to eq('groq')
  end

  it 'agrupa bajo "otros" un modelo sin pista de proveedor, en vez de descartarlo' do
    catalog = client_returning([{ 'model_name' => 'modelo-suelto' }]).model_catalog

    expect(catalog).to eq([{ name: 'modelo-suelto', provider: 'otros' }])
  end

  it 'ordena por proveedor y luego por modelo' do
    catalog = client_returning([
                                 { 'model_name' => 'gpt-4o', 'model_info' => { 'litellm_provider' => 'openai' } },
                                 { 'model_name' => 'claude', 'model_info' => { 'litellm_provider' => 'anthropic' } },
                                 { 'model_name' => 'gpt-4', 'model_info' => { 'litellm_provider' => 'openai' } }
                               ]).model_catalog

    expect(catalog.map { |m| m[:name] }).to eq(%w[claude gpt-4 gpt-4o])
  end

  it 'no duplica un modelo repetido en varias entradas' do
    catalog = client_returning([
                                 { 'model_name' => 'gpt-4', 'model_info' => { 'litellm_provider' => 'openai' } },
                                 { 'model_name' => 'gpt-4', 'model_info' => { 'litellm_provider' => 'openai' } }
                               ]).model_catalog

    expect(catalog.size).to eq(1)
  end

  it 'ignora filas sin nombre de modelo' do
    catalog = client_returning([{ 'model_info' => { 'litellm_provider' => 'openai' } }, 'basura']).model_catalog

    expect(catalog).to be_empty
  end

  it 'model_names sigue devolviendo la lista plana' do
    names = client_returning([
                               { 'model_name' => 'gpt-4', 'model_info' => { 'litellm_provider' => 'openai' } },
                               { 'model_name' => 'claude', 'model_info' => { 'litellm_provider' => 'anthropic' } }
                             ]).model_names

    expect(names).to eq(%w[claude gpt-4])
  end
end
