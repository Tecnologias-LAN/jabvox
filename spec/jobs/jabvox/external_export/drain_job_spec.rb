# frozen_string_literal: true

require 'rails_helper'

# Palancas 3 (vecino ruidoso) y 4 (coalescing) con el patrón correcto: Set por
# cuenta (dedup) + un drenador por cuenta que procesa en lotes. Sin rebote/busy-loop.
RSpec.describe Jabvox::ExternalExport::DrainJob do
  describe '.ensure_enqueued (un drenador por cuenta)' do
    it 'encola el drenador cuando toma el lock de encolado' do
      allow(Redis::Alfred).to receive(:set).and_return(true)
      expect(described_class).to receive(:perform_later).with(7)
      expect(described_class.ensure_enqueued(7)).to be(true)
    end

    it 'NO encola un segundo drenador si el lock ya está tomado (dedup)' do
      allow(Redis::Alfred).to receive(:set).and_return(false)
      expect(described_class).not_to receive(:perform_later)
      expect(described_class.ensure_enqueued(7)).to be(false)
    end

    it 'es fail-open: si Redis falla, encola igual (no perder el export)' do
      allow(Redis::Alfred).to receive(:set).and_raise(StandardError)
      expect(described_class).to receive(:perform_later).with(7)
      expect(described_class.ensure_enqueued(7)).to be(true)
    end
  end

  describe 'claves del Set y del lock' do
    it 'usa una clave de Set y de lock distinta por cuenta (aislamiento tenant)' do
      expect(described_class.pending_set_key(1)).not_to eq(described_class.pending_set_key(2))
      expect(described_class.enqueue_lock_key(1)).not_to eq(described_class.enqueue_lock_key(2))
    end
  end
end
