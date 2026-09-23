require 'rails_helper'

# Un proveedor lento podía bloquear el request durante decenas de minutos: cada llamada
# reintenta 4 veces con timeout de 30s y backoff, y un endpoint encadena varias. Con todos
# los workers de Puma esperando, una sola cuenta con el proveedor caído tumbaba al resto.
# El presupuesto de tiempo por instancia corta ese escenario.
RSpec.describe Jabvox::AiProvider::Client do
  # Adaptador que siempre responde 503 (error transitorio → dispara los reintentos).
  let(:always_failing) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = 0

      def request(_method, _path, **)
        @calls += 1
        { status: 503, body: nil, body_text: 'unavailable' }
      end
    end.new
  end

  describe 'presupuesto de tiempo' do
    it 'deja de reintentar cuando se agota el presupuesto' do
      client = described_class.new(adapter: always_failing, budget_seconds: 0)

      result = client.models_info

      expect(result).not_to be_success
      expect(result.status).to eq(504)
      # Con presupuesto agotado ni siquiera debe intentar la llamada.
      expect(always_failing.calls).to eq(0)
    end

    it 'comparte el presupuesto entre todas las llamadas de la misma instancia' do
      client = described_class.new(adapter: always_failing, budget_seconds: 0)

      client.models_info
      client.team_info('t1')
      client.list_keys('t1')

      # Ninguna llegó a la red: el presupuesto ya estaba agotado.
      expect(always_failing.calls).to eq(0)
    end

    it 'con budget_seconds: nil no limita (jobs en segundo plano)' do
      client = described_class.new(adapter: always_failing, budget_seconds: nil)

      expect(client.budget_exhausted?).to be false
    end

    it 'un presupuesto amplio no interfiere con una llamada normal' do
      ok_adapter = Class.new do
        def request(_method, _path, **) = { status: 200, body: { 'data' => [] }, body_text: '{}' }
      end.new
      client = described_class.new(adapter: ok_adapter, budget_seconds: 30)

      expect(client.models_info).to be_success
    end

    it 'el error de timeout es un mensaje para el usuario, sin detalles internos' do
      client = described_class.new(adapter: always_failing, budget_seconds: 0)

      error = client.models_info.error

      expect(error).to match(/tardó demasiado/)
      expect(error).not_to match(/Bearer|sk-|503/)
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'cada instancia lleva su propio presupuesto: una cuenta lenta no gasta el de otra' do
      cuenta_a = described_class.new(adapter: always_failing, budget_seconds: 0)
      cuenta_b = described_class.new(adapter: always_failing, budget_seconds: 30)

      expect(cuenta_a.budget_exhausted?).to be true
      expect(cuenta_b.budget_exhausted?).to be false
    end
  end
end
