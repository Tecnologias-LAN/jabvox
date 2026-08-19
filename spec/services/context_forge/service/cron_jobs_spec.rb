# frozen_string_literal: true

require 'rails_helper'

# Verifica el contrato de los métodos de cron del service. Usa una subclase de prueba que
# sobrescribe hermes_scoped_client para inyectar una conexión Faraday doble (sin stubear el
# objeto bajo prueba ni salir a la red).
RSpec.describe ContextForge::Service::CronJobs do
  let(:conn) { instance_double(Faraday::Connection) }
  let(:service) do
    fake_conn = conn
    Class.new(ContextForge::Service) do
      define_method(:hermes_scoped_client) { |_token| fake_conn }
    end.new
  end

  before { allow(ContextForge::Service).to receive(:hermes_url).and_return('https://hermes.example') }

  it 'lista los cron jobs con el scoped token de la cuenta' do
    body = { 'jobs' => [{ 'id' => 'c1', 'name' => 'Reporte', 'schedule' => '0 8 * * *' }] }
    allow(conn).to receive(:get).with('cron/jobs')
                                .and_return(instance_double(Faraday::Response, success?: true, body: body, status: 200))

    result = service.list_cron_jobs('TOK-25')
    expect(result).to be_success
    expect(result.data['jobs'].first['name']).to eq('Reporte')
  end

  it 'crea un cron job' do
    allow(conn).to receive(:post)
      .and_return(instance_double(Faraday::Response, success?: true, body: { 'id' => 'c2' }, status: 201))

    result = service.create_cron_job('TOK-25', { name: 'x', schedule: '0 9 * * 1' })
    expect(result).to be_success
  end

  it 'devuelve error legible si Hermes falla (403)' do
    allow(conn).to receive(:get)
      .and_return(instance_double(Faraday::Response, success?: false, body: { 'error' => 'nope' }, status: 403))

    result = service.list_cron_jobs('TOK-25')
    expect(result).not_to be_success
    expect(result.status).to eq(403)
  end
end
