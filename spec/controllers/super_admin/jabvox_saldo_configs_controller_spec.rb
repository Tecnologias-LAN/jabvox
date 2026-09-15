require 'rails_helper'

# api_key_jabvox se precargaba en claro en el <input> del formulario (a diferencia de
# api_secret_jabvox, que ya usaba password_field sin precarga) — cualquiera con "ver código
# fuente" en esa página de Super Admin veía la API key completa. Ahora ambos campos siguen
# el mismo patrón: password_field, sin precarga, y en blanco = conservar el valor actual.
RSpec.describe 'Super Admin Jabvox Saldo Config', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:config) do
    JabvoxSaldoConfig.create!(account: account, name_jabvox: 'Saldo', proxy_url_jabvox: 'http://proxy.example.com',
                              api_key_jabvox: 'super-secret-key', api_secret_jabvox: 'super-secret-secret')
  end

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/accounts/:account_id/jabvox_saldo_config' do
    it 'renders the api_key_jabvox field as a password_field, never precargando el valor real' do
      # Render aislado de la plantilla real (sin pasar por el layout de Super Admin, que en
      # este entorno de test intenta compilar assets de Vite en caliente y no aplica a lo
      # que se quiere probar aquí: que el <input> no lleve el secreto en su atributo value).
      config.update!(proxy_url_jabvox: 'http://127.0.0.1:1')
      html = ApplicationController.render(
        template: 'super_admin/jabvox_saldo_configs/show',
        layout: false,
        assigns: { config: config, status: { connected: false, balance: 0, currency: 'COP', message: 'stub' }, account: account }
      )

      expect(html).to include('type="password"')
      expect(html).not_to include('super-secret-key')
      expect(html).not_to include('super-secret-secret')
    end
  end

  describe 'PATCH /super_admin/accounts/:account_id/jabvox_saldo_config' do
    it 'keeps the current api_key_jabvox when the field is submitted blank' do
      patch "/super_admin/accounts/#{account.id}/jabvox_saldo_config",
            params: { jabvox_saldo_config: { name_jabvox: 'Renamed', api_key_jabvox: '', api_secret_jabvox: '' } }

      expect(config.reload.api_key_jabvox).to eq('super-secret-key')
      expect(config.name_jabvox).to eq('Renamed')
    end

    it 'updates api_key_jabvox when a new value is submitted' do
      patch "/super_admin/accounts/#{account.id}/jabvox_saldo_config",
            params: { jabvox_saldo_config: { api_key_jabvox: 'new-key', api_secret_jabvox: '' } }

      expect(config.reload.api_key_jabvox).to eq('new-key')
    end
  end
end
