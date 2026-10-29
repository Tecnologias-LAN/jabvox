# frozen_string_literal: true

require 'rails_helper'

# Guard anti-SSRF con RESOLUCIÓN: además de bloquear IPs literales internas y
# nombres de la lista negra, resuelve el host y rechaza si CUALQUIERA de sus IPs
# es interna (defensa anti DNS-rebinding). Si no resuelve, deja pasar para que la
# conexión real reporte el fallo (no depende de un resolvedor disponible).
RSpec.describe Jabvox::Flows::Nodes::Integration::UrlGuard do
  describe '.resolved_endpoint!' do
    it 'acepta un host que resuelve a una IP pública' do
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([Addrinfo.tcp('93.184.216.34', 80)])

      uri, ip = described_class.resolved_endpoint!('https://ejemplo-publico.com/x')

      expect(uri.host).to eq('ejemplo-publico.com')
      expect(ip).to eq('93.184.216.34')
    end

    it 'RECHAZA un nombre público que resuelve a una IP interna (DNS-rebinding)' do
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([Addrinfo.tcp('10.1.2.3', 80)])

      expect { described_class.resolved_endpoint!('https://parece-publico.com/x') }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /reservada o interna/)
    end

    it 'RECHAZA si ALGUNA de varias IPs es interna' do
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([Addrinfo.tcp('8.8.8.8', 80), Addrinfo.tcp('127.0.0.1', 80)])

      expect { described_class.resolved_endpoint!('https://mixto.com/x') }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /SSRF/)
    end

    it 'no bloquea cuando el host no resuelve (lo reportará la conexión)' do
      allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError)

      uri, ip = described_class.resolved_endpoint!('https://no-resuelve.com/x')

      expect(uri.host).to eq('no-resuelve.com')
      expect(ip).to be_nil
    end

    it 'bloquea una IP literal interna sin intentar resolver' do
      expect(Addrinfo).not_to receive(:getaddrinfo)

      expect { described_class.resolved_endpoint!('http://127.0.0.1:8080/x') }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /SSRF/)
    end

    it 'bloquea los nombres de la lista negra antes de resolver' do
      expect(Addrinfo).not_to receive(:getaddrinfo)

      expect { described_class.resolved_endpoint!('http://metadata.google.internal/x') }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /bloqueado/)
    end

    it 'rechaza esquemas no http/https' do
      expect { described_class.resolved_endpoint!('file:///etc/passwd') }
        .to raise_error(Jabvox::Flows::Engine::ExecutionError, /esquema/)
    end
  end
end
