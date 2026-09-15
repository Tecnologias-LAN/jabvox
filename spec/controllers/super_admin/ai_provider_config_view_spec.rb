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

  it 'ofrece sincronizar con el proveedor' do
    expect(render_accounts_tab).to include('Sincronizar ahora')
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
