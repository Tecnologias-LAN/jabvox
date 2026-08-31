# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Integration::HttpRequestNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  describe described_class do
    it 'devuelve status, headers y data con el cuerpo JSON parseado' do
      stub_request(:get, 'https://api.ejemplo.com/v1/clientes')
        .to_return(status: 200, body: '{"nombre":"Ana"}', headers: { 'Content-Type' => 'application/json' })

      result = run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/v1/clientes' })

      expect(result).to be_ok
      expect(result.output['status']).to eq(200)
      expect(result.output['data']).to eq('nombre' => 'Ana')
      expect(result.output['headers']['content-type']).to include('application/json')
    end

    it 'deja el cuerpo crudo cuando el Content-Type no es JSON' do
      stub_request(:get, 'https://api.ejemplo.com/texto')
        .to_return(status: 200, body: 'hola', headers: { 'Content-Type' => 'text/plain' })

      expect(run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/texto' }).output['data'])
        .to eq('hola')
    end

    it 'marca ok en false con "HTTP <status>" cuando responde 500' do
      stub_request(:get, 'https://api.ejemplo.com/roto').to_return(status: 500, body: 'boom')

      result = run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/roto' })

      expect(result).not_to be_ok
      expect(result.error).to eq('HTTP 500')
      # El payload sigue disponible para depurar aunque el paso falle.
      expect(result.output['status']).to eq(500)
    end

    it 'envía el método, las cabeceras y el cuerpo configurados' do
      stub = stub_request(:post, 'https://api.ejemplo.com/alta')
             .with(body: '{"nombre":"Ana"}', headers: { 'X-Token' => 'abc', 'Content-Type' => 'application/json' })
             .to_return(status: 201, body: '')

      result = run_node(described_class, ctx,
                        { 'url' => 'https://api.ejemplo.com/alta', 'method' => 'POST',
                          'headers' => { 'X-Token' => 'abc' }, 'body' => { 'nombre' => 'Ana' } })

      expect(result).to be_ok
      expect(stub).to have_been_requested
    end

    it 'NO sigue la redirección 302 (una 302 a una IP interna burlaría el guard)' do
      stub_request(:get, 'https://api.ejemplo.com/redirige')
        .to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data' })
      interna = stub_request(:get, 'http://169.254.169.254/latest/meta-data')

      result = run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/redirige' })

      expect(result.output['status']).to eq(302)
      expect(interna).not_to have_been_requested
    end

    it 'rechaza un método HTTP no soportado' do
      expect(run_node(described_class, ctx,
                      { 'url' => 'https://api.ejemplo.com/x', 'method' => 'TRACE' }).error)
        .to match(/no está soportado/)
    end

    describe 'timeout' do
      it 'con timeoutMs vacío aplica el respaldo de 15 s, no 0' do
        stub_request(:get, 'https://api.ejemplo.com/x').to_return(status: 200, body: '')
        expect(Net::HTTP).to receive(:start)
          .with(anything, anything, hash_including(open_timeout: 15.0, read_timeout: 15.0))
          .and_call_original

        run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/x', 'timeoutMs' => '' })
      end

      it 'con timeoutMs=0 acota al mínimo de 1 s en vez de dejarlo infinito' do
        stub_request(:get, 'https://api.ejemplo.com/x').to_return(status: 200, body: '')
        expect(Net::HTTP).to receive(:start)
          .with(anything, anything, hash_including(open_timeout: 1.0, read_timeout: 1.0))
          .and_call_original

        run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/x', 'timeoutMs' => 0 })
      end

      it 'acota el timeout al máximo de 120 s' do
        stub_request(:get, 'https://api.ejemplo.com/x').to_return(status: 200, body: '')
        expect(Net::HTTP).to receive(:start)
          .with(anything, anything, hash_including(open_timeout: 120.0, read_timeout: 120.0))
          .and_call_original

        run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/x', 'timeoutMs' => 999_999 })
      end

      it 'informa del tiempo de espera agotado sin dejar escapar la excepción' do
        stub_request(:get, 'https://api.ejemplo.com/lento').to_timeout

        expect(run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/lento' }).error)
          .to match(/tiempo de espera/)
      end
    end

    describe 'protección SSRF' do
      it 'rechaza la URL vacía diciendo qué campo falta' do
        expect(run_node(described_class, ctx, { 'url' => '' }).error).to match(/URL.*vacía/)
      end

      it 'rechaza una URL inválida' do
        expect(run_node(described_class, ctx, { 'url' => 'http://[no valida' }).error)
          .to match(/no es válida|no está permitido/)
      end

      it 'rechaza el esquema file:' do
        expect(run_node(described_class, ctx, { 'url' => 'file:///etc/passwd' }).error)
          .to match(/esquema "file" no está permitido/)
      end

      it 'rechaza otros esquemas no http (gopher, ftp)' do
        expect(run_node(described_class, ctx, { 'url' => 'ftp://ejemplo.com/x' }).error)
          .to match(/no está permitido/)
      end

      # Cada forma en la que un atacante puede escribir un destino interno.
      {
        'localhost' => 'http://localhost/x',
        'metadata de Google' => 'http://metadata.google.internal/x',
        'metadatos AWS/link-local' => 'http://169.254.169.254/latest/meta-data',
        'privada 10/8' => 'http://10.0.0.5/x',
        'privada 172.16/12' => 'http://172.20.1.1/x',
        'privada 192.168/16' => 'http://192.168.1.1/x',
        'loopback 127/8' => 'http://127.0.0.1:3000/x',
        'CGNAT 100.64/10' => 'http://100.64.0.1/x',
        'cero 0/8' => 'http://0.0.0.0/x',
        'loopback IPv6' => 'http://[::1]/x',
        'loopback IPv6 sin comprimir' => 'http://[0:0:0:0:0:0:0:1]/x',
        'ULA IPv6 fc00::/7' => 'http://[fd00::1]/x',
        'link-local IPv6 fe80::/10' => 'http://[fe80::1]/x',
        'IPv4 mapeada dotted' => 'http://[::ffff:127.0.0.1]/x',
        'IPv4 mapeada HEX (loopback)' => 'http://[::ffff:7f00:1]/x',
        'IPv4 mapeada HEX (metadatos)' => 'http://[::ffff:a9fe:a9fe]/x'
      }.each do |caso, url|
        it "bloquea #{caso}: #{url}" do
          result = run_node(described_class, ctx, { 'url' => url })

          expect(result).not_to be_ok
          expect(result.error).to match(/SSRF/)
          # Ni siquiera se intentó la conexión.
          expect(a_request(:any, /.*/)).not_to have_been_made
        end
      end

      it 'permite un host público normal' do
        stub_request(:get, 'https://api.ejemplo.com/ok').to_return(status: 200, body: '')

        expect(run_node(described_class, ctx, { 'url' => 'https://api.ejemplo.com/ok' })).to be_ok
      end
    end
  end

  describe Jabvox::Flows::Nodes::Integration::GraphqlNode do
    let(:url) { 'https://api.ejemplo.com/graphql' }

    it 'envía query y variables por POST y devuelve status y data' do
      stub = stub_request(:post, url)
             .with(body: { 'query' => '{ me { id } }', 'variables' => { 'x' => 1 } })
             .to_return(status: 200, body: '{"data":{"me":{"id":7}}}',
                        headers: { 'Content-Type' => 'application/json' })

      result = run_node(described_class, ctx,
                        { 'url' => url, 'query' => '{ me { id } }', 'variables' => { 'x' => 1 } })

      expect(result).to be_ok
      expect(result.output).to eq('status' => 200, 'data' => { 'data' => { 'me' => { 'id' => 7 } } })
      expect(stub).to have_been_requested
    end

    it 'manda variables vacías cuando no se configuran' do
      stub = stub_request(:post, url)
             .with(body: { 'query' => '{ me }', 'variables' => {} })
             .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      run_node(described_class, ctx, { 'url' => url, 'query' => '{ me }' })

      expect(stub).to have_been_requested
    end

    it 'marca ok en false si el cuerpo trae errors aunque el status sea 200' do
      stub_request(:post, url)
        .to_return(status: 200, body: '{"errors":[{"message":"Campo desconocido"}]}',
                   headers: { 'Content-Type' => 'application/json' })

      result = run_node(described_class, ctx, { 'url' => url, 'query' => '{ nope }' })

      expect(result).not_to be_ok
      expect(result.error).to eq('GraphQL devolvió errores.')
      expect(result.output['status']).to eq(200)
    end

    it 'marca ok en false con HTTP <status> si el endpoint responde 500' do
      stub_request(:post, url).to_return(status: 500, body: '')

      result = run_node(described_class, ctx, { 'url' => url, 'query' => '{ me }' })

      expect(result).not_to be_ok
      expect(result.error).to eq('HTTP 500')
    end

    it 'exige la consulta' do
      expect(run_node(described_class, ctx, { 'url' => url, 'query' => '' }).error)
        .to match(/Falta la consulta GraphQL/)
    end

    it 'aplica el mismo guard SSRF en la forma hex mapeada' do
      expect(run_node(described_class, ctx, { 'url' => 'http://[::ffff:a9fe:a9fe]/graphql', 'query' => '{ me }' }).error)
        .to match(/SSRF/)
    end
  end

  describe Jabvox::Flows::Nodes::Integration::WebhookOutNode do
    let(:url) { 'https://hooks.ejemplo.com/entrada' }

    it 'hace POST del payload y devuelve status y data' do
      stub = stub_request(:post, url)
             .with(body: { 'evento' => 'lead.creado' }, headers: { 'Content-Type' => 'application/json' })
             .to_return(status: 200, body: '{"recibido":true}',
                        headers: { 'Content-Type' => 'application/json' })

      result = run_node(described_class, ctx, { 'url' => url, 'payload' => { 'evento' => 'lead.creado' } })

      expect(result).to be_ok
      expect(result.output).to eq('status' => 200, 'data' => { 'recibido' => true })
      expect(stub).to have_been_requested
    end

    it 'manda un objeto vacío cuando no hay payload' do
      stub = stub_request(:post, url).with(body: '{}').to_return(status: 204, body: '')

      expect(run_node(described_class, ctx, { 'url' => url })).to be_ok
      expect(stub).to have_been_requested
    end

    it 'marca ok en false con HTTP <status> cuando el destino responde 404' do
      stub_request(:post, url).to_return(status: 404, body: '')

      result = run_node(described_class, ctx, { 'url' => url })

      expect(result).not_to be_ok
      expect(result.error).to eq('HTTP 404')
    end

    it 'aplica el guard SSRF al destino' do
      expect(run_node(described_class, ctx, { 'url' => 'http://127.0.0.1:9000/hook' }).error).to match(/SSRF/)
    end

    it 'informa cuando el host no resuelve' do
      stub_request(:post, url).to_raise(SocketError.new('getaddrinfo: nodename nor servname provided'))

      expect(run_node(described_class, ctx, { 'url' => url }).error).to match(/No se pudo conectar/)
    end
  end
end
