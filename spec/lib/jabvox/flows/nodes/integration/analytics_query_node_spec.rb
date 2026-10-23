# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# integration.analytics_query — SELECT read-only contra una fuente de Analytics.
# Toda la seguridad (anti-SSRF, SQL read-only, scope de cuenta) vive en
# AnalyticsQueryService, probado aparte; aquí se verifica que el NODO valida sus
# params, elige el modo correcto y traduce los errores del servicio a fallo de paso.
RSpec.describe Jabvox::Flows::Nodes::Integration::AnalyticsQueryNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  # Resultado que devuelve el servicio (duck-typed: rows/columns/row_count/elapsed_ms).
  let(:fake_result) do
    Struct.new(:rows, :columns, :row_count, :elapsed_ms).new(
      [{ 'name' => 'Ana' }, { 'name' => 'Beto' }], %w[name], 2, 12
    )
  end

  it 'falla cuando no se eligió la fuente de datos' do
    result = run_node(described_class, ctx, { 'mode' => 'sql', 'sql' => 'SELECT 1' })

    expect(result).not_to be_ok
    expect(result.error).to match(/fuente de datos/i)
  end

  it 'en modo sql delega el SELECT y los binds al servicio y expone las filas' do
    service = instance_double(Jabvox::Flows::AnalyticsQueryService)
    expect(Jabvox::Flows::AnalyticsQueryService).to receive(:new).with(
      account_id: account.id, data_source_id: '7', limit: 50
    ).and_return(service)
    # El SELECT se lee CRUDO (sus {{marcadores}} se conservan para que el servicio
    # los ligue como binds); los valores salen de sqlParams.
    expect(service).to receive(:run_sql)
      .with('SELECT name FROM clientes WHERE dia = {{hoy}}', params: { 'hoy' => '2026-10-22' })
      .and_return(fake_result)

    result = run_node(described_class, ctx, {
                        'dataSourceId' => '7', 'mode' => 'sql', 'limit' => 50,
                        'sql' => 'SELECT name FROM clientes WHERE dia = {{hoy}}',
                        'sqlParams' => { 'hoy' => '2026-10-22' }
                      })

    expect(result).to be_ok
    expect(result.output['rows']).to eq([{ 'name' => 'Ana' }, { 'name' => 'Beto' }])
    expect(result.output['row_count']).to eq(2)
    expect(result.output['columns']).to eq(%w[name])
  end

  it 'en modo builder arma la consulta con tabla, columnas, filtros y orden' do
    service = instance_double(Jabvox::Flows::AnalyticsQueryService)
    allow(Jabvox::Flows::AnalyticsQueryService).to receive(:new).and_return(service)
    expect(service).to receive(:run_builder).with(
      table: 'clientes', columns: %w[name phone],
      filters: [{ 'col' => 'activo', 'op' => 'equals', 'value' => true }],
      order_by: 'name', order_dir: 'asc'
    ).and_return(fake_result)

    result = run_node(described_class, ctx, {
                        'dataSourceId' => '7', 'mode' => 'builder', 'table' => 'clientes',
                        'columns' => %w[name phone],
                        'filters' => [{ 'col' => 'activo', 'op' => 'equals', 'value' => true }],
                        'orderBy' => 'name', 'orderDir' => 'asc'
                      })

    expect(result).to be_ok
    expect(result.output['row_count']).to eq(2)
  end

  it 'traduce un QueryError del servicio a fallo del paso (sin reventar el run)' do
    service = instance_double(Jabvox::Flows::AnalyticsQueryService)
    allow(Jabvox::Flows::AnalyticsQueryService).to receive(:new).and_return(service)
    allow(service).to receive(:run_sql)
      .and_raise(Jabvox::Flows::AnalyticsQueryService::QueryError, 'solo se permiten consultas SELECT')

    result = run_node(described_class, ctx,
                      { 'dataSourceId' => '7', 'mode' => 'sql', 'sql' => 'DROP TABLE x' })

    expect(result).not_to be_ok
    expect(result.error).to match(/SELECT/)
  end

  it 'acepta columnas como texto separado por comas (no solo arreglo)' do
    service = instance_double(Jabvox::Flows::AnalyticsQueryService)
    allow(Jabvox::Flows::AnalyticsQueryService).to receive(:new).and_return(service)
    expect(service).to receive(:run_builder)
      .with(hash_including(columns: %w[name phone email]))
      .and_return(fake_result)

    run_node(described_class, ctx, {
               'dataSourceId' => '7', 'mode' => 'builder', 'table' => 't',
               'columns' => 'name, phone , email'
             })
  end
end
