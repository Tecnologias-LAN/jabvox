# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::RedisLock do
  describe '.with_lock' do
    it 'ejecuta el bloque y devuelve su valor cuando toma el lock' do
      allow(described_class).to receive_messages(acquire: true, start_heartbeat: nil, release: nil)
      result = described_class.with_lock('k') { 42 }
      expect(result).to eq(42)
    end

    it 'no ejecuta el bloque y devuelve NOT_ACQUIRED si el lock está tomado' do
      allow(described_class).to receive(:acquire).and_return(false)
      ran = false
      result = described_class.with_lock('k') { ran = true }
      expect(ran).to be(false)
      expect(result).to eq(described_class::NOT_ACQUIRED)
    end

    it 'libera el lock aunque el bloque lance' do
      allow(described_class).to receive_messages(acquire: true, start_heartbeat: nil)
      expect(described_class).to receive(:release).with('k', anything)
      expect { described_class.with_lock('k') { raise 'boom' } }.to raise_error('boom')
    end

    it 'usa un token único por invocación (no se puede robar el lock)' do
      tokens = []
      allow(described_class).to receive(:acquire) do |_k, token, _ttl|
        tokens << token
        true
      end
      allow(described_class).to receive_messages(start_heartbeat: nil, release: nil)
      described_class.with_lock('k') { 1 }
      described_class.with_lock('k') { 1 }
      expect(tokens.uniq.size).to eq(2)
    end
  end

  describe '.acquire' do
    it 'es fail-open: si Redis falla, devuelve false (no bloquea el trabajo)' do
      allow(Redis::Alfred).to receive(:set).and_raise(StandardError)
      expect(described_class.acquire('k', 'tok', 60)).to be(false)
    end
  end

  describe 'fencing (Handle#held?)' do
    it 'pasa un Handle al bloque cuyo held? refleja si seguimos siendo dueños' do
      allow(described_class).to receive_messages(acquire: true, start_heartbeat: nil, release: nil)
      handle = nil
      described_class.with_lock('k') { |lock| handle = lock }
      # Sigue siendo nuestro token -> held? true
      allow(Redis::Alfred).to receive(:get).with('k').and_return(handle.token)
      expect(handle.held?).to be(true)
      # Otro proceso tomó el lock -> held? false (fencing dispara el abort)
      allow(Redis::Alfred).to receive(:get).with('k').and_return('otro-token')
      expect(handle.held?).to be(false)
    end

    it '.owner? es fail-closed: si Redis falla, devuelve false (aborta la escritura)' do
      allow(Redis::Alfred).to receive(:get).and_raise(StandardError)
      expect(described_class.owner?('k', 'tok')).to be(false)
    end
  end
end
