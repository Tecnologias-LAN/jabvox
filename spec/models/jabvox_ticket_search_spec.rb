# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxTicket do
  let(:account) { create(:account) }

  describe '.accent_insensitive_search' do
    let!(:ticket) do
      create(:jabvox_ticket, account: account, title_jabvox: 'Error en producción',
                             description_jabvox: 'la máquina está caída')
    end

    it 'encuentra por el título ignorando acentos (sin tilde → con tilde)' do
      expect(described_class.accent_insensitive_search('produccion')).to include(ticket)
    end

    it 'encuentra por el título con acentos también' do
      expect(described_class.accent_insensitive_search('producción')).to include(ticket)
    end

    it 'encuentra por la descripción ignorando acentos' do
      expect(described_class.accent_insensitive_search('maquina')).to include(ticket)
    end

    it 'soporta búsqueda por prefijo' do
      expect(described_class.accent_insensitive_search('produc')).to include(ticket)
    end

    it 'no devuelve resultados para términos ausentes' do
      expect(described_class.accent_insensitive_search('inexistente')).not_to include(ticket)
    end
  end
end
