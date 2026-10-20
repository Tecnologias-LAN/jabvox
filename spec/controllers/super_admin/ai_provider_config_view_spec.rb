require 'rails_helper'

# La pestaña "Por cuenta" debe ofrecer un SELECTOR de cuentas (antes era un campo numérico
# donde había que adivinar el id) y listar los teams del proveedor que aún no tienen cuenta.
# Se renderiza la plantilla real sin layout (el layout de Super Admin intenta compilar Vite
# en caliente en este entorno y no aporta a lo que se prueba aquí).
RSpec.describe 'Super Admin AI Provider Config — vista', type: :request do
  let(:config) { JabvoxAiProviderConfig.instance }
  let!(:account_one) { create(:account, name: 'Cliente Uno') }
  let!(:account_two) { create(:account, name: 'Cliente Dos') }
  let!(:orphan) do
    JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-sin-duenio',
                                    team_alias_jabvox: 'cliente-misterioso',
                                    remote_max_budget_jabvox: 42.5,
                                    origin_jabvox: 'litellm')
  end

  def render_accounts_tab
    ApplicationController.render(
      template: 'super_admin/ai_provider_config/show',
      layout: false,
      assigns: {
        config: config, summary: config.safe_summary, tab: 'accounts', rows: [],
        account_options: [["##{account_one.id} — Cliente Uno", account_one.id],
                          ["##{account_two.id} — Cliente Dos", account_two.id]],
        orphans: [orphan]
      }
    )
  end

  it 'usa un selector de cuentas en vez de pedir el id a ciegas' do
    html = render_accounts_tab

    expect(html).to include('data-jabvox-account-select')
    expect(html).to include('Cliente Uno')
    expect(html).to include('Cliente Dos')
    # Ya no existe el <input type="number" name="account_id"> original.
    expect(html).not_to match(/name="account_id"[^>]*type="number"/)
  end

  it 'ofrece actualizar y forzar la sincronización con el proveedor' do
    html = render_accounts_tab

    # El botón se renombró: la pestaña ya sincroniza al abrirse, y "Actualizar ahora"
    # fuerza una pasada inmediata (?resync=1).
    expect(html).to include('Actualizar ahora')
    expect(html).to include('resync=1')
    expect(html).to include('Sincronizar (forzado)')
  end

  it 'lista los teams sin cuenta con su tope remoto y un formulario para ligarlos' do
    html = render_accounts_tab

    expect(html).to include('cliente-misterioso')
    expect(html).to include('team-sin-duenio')
    expect(html).to include('$42.50')
    expect(html).to include('provider_account_id')
  end

  it 'incluye el buscador para filtrar cuentas' do
    expect(render_accounts_tab).to include('Filtrar por nombre o #id')
  end

  it 'el diagnóstico de un team no imprime la key en claro, solo el hash truncado' do
    inspection = {
      team_id: 'team-x', total_count: 1, total_pages: 1, team_models: ['mock/model-a'],
      keys: [{ alias: 'mia', team_id: 'team-x', models: ['mock/model-a'],
               spend: 1.5, max_budget: 10, blocked: false,
               token: 'abcdef123456' }]
    }

    html = ApplicationController.render(
      template: 'super_admin/ai_provider_config/show', layout: false,
      assigns: { config: config, summary: config.safe_summary, tab: 'accounts', rows: [],
                 account_options: [], orphans: [], available_models: ['mock/model-a'],
                 inspection: inspection }
    )

    expect(html).to include('mia')
    expect(html).to include('abcdef123456')
    # El hash llega truncado desde el servicio; nunca una key sk-... completa.
    expect(html).not_to match(/sk-[A-Za-z0-9_-]{10,}/)
  end

  it 'agrupa los modelos por proveedor con casillas, no un select de lista' do
    linked = JabvoxAiProviderAccount.create!(account: account_one, team_id_jabvox: 'team-g',
                                             remote_models_jabvox: ['gpt-4'])
    rows = [{ account: account_one, plan: nil, provider_account: linked, connected: true }]

    html = ApplicationController.render(
      template: 'super_admin/ai_provider_config/show', layout: false,
      assigns: { config: config, summary: config.safe_summary, tab: 'accounts', rows: rows,
                 account_options: [], orphans: [],
                 available_models: %w[gpt-4 gpt-4o claude],
                 models_by_provider: { 'openai' => %w[gpt-4 gpt-4o],
                                       'anthropic' => ['claude'] } }
    )

    # Casillas por modelo, agrupadas bajo el nombre del proveedor.
    expect(html).to include('type="checkbox"')
    expect(html).to include('name="models[]"')
    expect(html).to include('openai')
    expect(html).to include('anthropic')
    expect(html).to include('gpt-4o')
    # El modelo ya asignado viene marcado.
    expect(html).to match(/value="gpt-4"[^>]*checked/)
    # Ya no se usa un <select multiple> (mostraba la lista separada por comas).
    expect(html).not_to include('multiple="multiple"')
  end

  it 'ofrece el selector de modelos por team cuando hay catálogo' do
    linked = JabvoxAiProviderAccount.create!(account: account_one, team_id_jabvox: 'team-m',
                                             remote_models_jabvox: ['mock/model-a'])
    rows = [{ account: account_one, plan: nil, provider_account: linked, connected: true }]

    html = ApplicationController.render(
      template: 'super_admin/ai_provider_config/show', layout: false,
      assigns: { config: config, summary: config.safe_summary, tab: 'accounts', rows: rows,
                 account_options: [], orphans: [],
                 available_models: ['mock/model-a', 'mock/model-b'],
                 models_by_provider: { 'mock' => ['mock/model-a', 'mock/model-b'] } }
    )

    expect(html).to include('Guardar modelos')
    expect(html).to include('mock/model-b')
  end

  it 'nunca imprime la master key' do
    config.update!(master_key_jabvox: 'sk-secretisima-12345', base_url_jabvox: 'https://proxy.example.com')

    html = ApplicationController.render(
      template: 'super_admin/ai_provider_config/show', layout: false,
      assigns: { config: config, summary: config.safe_summary, tab: 'connection' }
    )

    expect(html).not_to include('sk-secretisima-12345')
    expect(html).to include('type="password"')
  end
end
