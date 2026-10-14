require 'rails_helper'

RSpec.describe Jabvox::Provisioner::HandlersPlatform do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  describe 'catálogo y manual' do
    it 'documenta TODAS las operaciones registradas' do
      # Sin doc, quien consume la API sabe que puede llamar la operación pero no con qué
      # parámetros, y acaba adivinando nombres.
      expect(Jabvox::Provisioner::OperationDocs.undocumented).to be_empty
    end

    it 'no documenta operaciones que no existen' do
      huerfanas = Jabvox::Provisioner::OperationDocs::DOCS.keys -
                  Jabvox::Provisioner::OperationRegistry.catalog.keys
      expect(huerfanas).to be_empty
    end

    it 'cada operación tiene un handler implementado en algún módulo' do
      modulos = [Jabvox::Provisioner::Handlers,
                 Jabvox::Provisioner::HandlersAdmin,
                 described_class]
      sin_handler = Jabvox::Provisioner::OperationRegistry::OPERATIONS.reject do |_op, meta|
        modulos.any? { |m| m.respond_to?(meta[:handler]) }
      end
      expect(sin_handler.keys).to be_empty
    end

    it 'no expone ninguna operación destructiva' do
      # La API Provisioner lee, crea y edita; nunca borra.
      destructivas = Jabvox::Provisioner::OperationRegistry::OPERATIONS.keys.grep(/delete|destroy|remove/)
      expect(destructivas).to be_empty
    end
  end

  describe 'permisos de los recursos nuevos' do
    it 'permite crear y editar saldo, hermes y automatizaciones' do
      todo = JabvoxProvisionerApiToken::RESOURCES.index_with { JabvoxProvisionerApiToken::ACTIONS }
      permisos = JabvoxProvisionerApiToken.sanitize_permissions(todo)

      expect(permisos['saldo']).to match_array(%w[view edit create])
      expect(permisos['hermes_instances']).to match_array(%w[view edit create])
      expect(permisos['automations']).to match_array(%w[view edit create])
    end

    it 'mantiene las transacciones y pasarelas en solo lectura' do
      todo = JabvoxProvisionerApiToken::RESOURCES.index_with { JabvoxProvisionerApiToken::ACTIONS }
      permisos = JabvoxProvisionerApiToken.sanitize_permissions(todo)

      expect(permisos['transactions']).to eq(['view'])
      expect(permisos['payment_gateways']).to eq(['view'])
    end
  end

  describe '#hermes_create' do
    let(:params) do
      { 'account_id' => account.id, 'name' => 'Mi agente', 'hermes_agent_name' => 'mi-agente',
        'base_url' => 'http://10.147.200.3:8080/p/mi-agente/v1', 'token' => 'bearer-x',
        'allowed_ips' => '10.147.17.0/24, 203.0.113.5' }
    end

    it 'crea la conexión y devuelve su action_token' do
      result = described_class.hermes_create(params)
      conn = result[:connection]

      expect(conn[:hermes_agent]).to eq('mi-agente')
      expect(conn[:allowed_ips]).to eq(['10.147.17.0/24', '203.0.113.5'])
      expect(conn[:action_token]).to be_present
      expect(account.jabvox_hermes_connections.count).to eq(1)
    end

    it 'acepta la allowlist como array' do
      result = described_class.hermes_create(params.merge('allowed_ips' => ['10.147.17.5']))
      expect(result[:connection][:allowed_ips]).to eq(['10.147.17.5'])
    end

    # Una conexión sin IPs no puede ejecutar nada (ip_allowed? la rechaza), así que crearla
    # vacía dejaría un agente inservible y un fallo invisible.
    it 'rechaza una allowlist vacía' do
      expect { described_class.hermes_create(params.merge('allowed_ips' => '')) }
        .to raise_error(/allowed_ips es requerida/)
    end

    it 'rechaza una allowlist que solo trae cadenas en blanco' do
      # Array('') devuelve [''], que NO está vacío: el caso que se colaba antes.
      expect { described_class.hermes_create(params.merge('allowed_ips' => [''])) }
        .to raise_error(/allowed_ips es requerida/)
    end

    it 'rechaza una IP mal escrita' do
      expect { described_class.hermes_create(params.merge('allowed_ips' => 'no-es-ip')) }
        .to raise_error(/IP invalida/)
    end

    it 'exige los campos del formulario' do
      expect { described_class.hermes_create(params.merge('name' => '')) }.to raise_error(/name es requerido/)
      expect { described_class.hermes_create(params.merge('base_url' => '')) }.to raise_error(/base_url es requerida/)
    end
  end

  describe 'aislamiento entre cuentas' do
    it 'no alcanza la conexión de otra cuenta' do
      ajena = described_class.hermes_create(
        'account_id' => other_account.id, 'name' => 'Ajeno', 'hermes_agent_name' => 'ajeno',
        'base_url' => 'http://10.147.200.9:8080/p/ajeno/v1', 'allowed_ips' => '10.147.17.9'
      )[:connection]

      expect { described_class.hermes_get('account_id' => account.id, 'connection_id' => ajena[:id]) }
        .to raise_error(/no encontrada en esta cuenta/)
    end
  end

  describe '#hermes_update' do
    let!(:conn) do
      described_class.hermes_create(
        'account_id' => account.id, 'name' => 'Mi agente', 'hermes_agent_name' => 'mi-agente',
        'base_url' => 'http://10.147.200.3:8080/p/mi-agente/v1', 'token' => 'bearer-original',
        'allowed_ips' => '10.147.17.0/24'
      )[:connection]
    end

    it 'conserva el token cuando llega en blanco' do
      described_class.hermes_update('account_id' => account.id, 'connection_id' => conn[:id],
                                    'name' => 'Renombrado', 'token' => '')
      record = account.jabvox_hermes_connections.find(conn[:id])

      expect(record.name_jabvox).to eq('Renombrado')
      expect(record.token_jabvox).to eq('bearer-original')
    end

    it 'no deja vaciar la allowlist' do
      expect do
        described_class.hermes_update('account_id' => account.id, 'connection_id' => conn[:id],
                                      'allowed_ips' => '')
      end.to raise_error(/no puede quedar vacia/)
    end
  end

  describe '#hermes_rotate_token' do
    it 'cambia el token e invalida el anterior' do
      conn = described_class.hermes_create(
        'account_id' => account.id, 'name' => 'Mi agente', 'hermes_agent_name' => 'mi-agente',
        'base_url' => 'http://10.147.200.3:8080/p/mi-agente/v1', 'allowed_ips' => '10.147.17.0/24'
      )[:connection]
      anterior = conn[:action_token]

      nuevo = described_class.hermes_rotate_token(
        'account_id' => account.id, 'connection_id' => conn[:id]
      )[:connection][:action_token]

      expect(nuevo).to be_present
      expect(nuevo).not_to eq(anterior)
    end
  end

  describe 'automatizaciones' do
    let!(:rule) do
      account.automation_rules.create!(
        name: 'Saludo', event_name: 'conversation_created',
        conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'] }],
        actions: [{ action_name: 'assign_team', action_params: [] }]
      )
    end

    it 'lista y desactiva una regla' do
      expect(described_class.automations_list('account_id' => account.id)[:automations].first[:name]).to eq('Saludo')

      result = described_class.automations_set_active(
        'account_id' => account.id, 'id' => rule.id, 'active' => false
      )
      expect(result[:automation][:active]).to be(false)
      expect(rule.reload.active).to be(false)
    end

    it 'no alcanza una regla de otra cuenta' do
      ajena = other_account.automation_rules.create!(
        name: 'Ajena', event_name: 'conversation_created',
        conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'] }],
        actions: [{ action_name: 'assign_team', action_params: [] }]
      )

      expect { described_class.automations_get('account_id' => account.id, 'id' => ajena.id) }
        .to raise_error(/no encontrada/)
    end
  end

  describe 'módulos de la cuenta' do
    it 'devuelve el catálogo con la clave corta que acepta set' do
      catalogo = Jabvox::Provisioner::Handlers.get_account_modules('id' => account.id)[:catalog]
      cdr = catalogo.find { |m| m[:key] == 'cdr' }

      expect(cdr[:column]).to eq('jabvox_cdr_enabled_jabvox')
      expect(cdr[:label]).to be_present

      Jabvox::Provisioner::Handlers.set_account_modules('id' => account.id, 'modules' => { 'cdr' => true })
      expect(account.reload.jabvox_cdr_enabled_jabvox).to be(true)
    end
  end
end
