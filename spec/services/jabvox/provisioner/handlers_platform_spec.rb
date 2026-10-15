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

  describe 'agentes del Chat IA' do
    let!(:usuario) do
      u = create(:user, account: account)
      account.account_users.find_by(user_id: u.id)&.update!(role: :administrator)
      u
    end

    def crear_agente(user: usuario, nombre: 'Agente de prueba', **extra)
      described_class.hermes_agents_create(
        { 'account_id' => account.id, 'user_id' => user.id, 'name' => nombre }.merge(extra)
      )[:agent]
    end

    def crear_hermes(nombre: 'Hermes', agente_id: nil)
      params = { 'account_id' => account.id, 'name' => nombre, 'hermes_agent_name' => nombre.downcase,
                 'base_url' => 'http://10.147.200.3:8080/p/hermes/v1', 'allowed_ips' => '10.147.17.0/24' }
      params['agent_id'] = agente_id if agente_id
      described_class.hermes_create(params)
    end

    it 'crea el agente ligado al usuario y le deriva sus permisos' do
      agente = crear_agente(nombre: 'Agente de Keiner')

      expect(agente[:name]).to eq('Agente de Keiner')
      expect(agente[:user][:id]).to eq(usuario.id)
      # Sin permisos derivados el agente no podría ejecutar nada.
      expect(JabvoxHermesUserPermission.exists?(account_id: account.id, user_id: usuario.id)).to be(true)
    end

    it 'liga el Hermes al agente en el mismo paso de crearlo' do
      agente = crear_agente
      resultado = crear_hermes(agente_id: agente[:id])

      expect(resultado[:agent][:connection_ids]).to eq([resultado[:connection][:id]])
      expect(resultado[:warning]).to be_nil
    end

    # Un Hermes sin agente no aparece en el Chat IA: crearlo suelto en silencio dejaría al
    # aprovisionador creyendo que terminó.
    it 'avisa cuando el Hermes queda sin agente' do
      resultado = crear_hermes

      expect(resultado[:agent]).to be_nil
      expect(resultado[:warning]).to match(/NO esta ligado a ningun agente/)
    end

    it 'liga y desliga conexiones de un agente existente' do
      agente = crear_agente
      conn = crear_hermes[:connection]

      ligado = described_class.hermes_agents_set_connections(
        'account_id' => account.id, 'agent_id' => agente[:id], 'connection_ids' => [conn[:id]]
      )
      expect(ligado[:agent][:connection_ids]).to eq([conn[:id]])

      vacio = described_class.hermes_agents_set_connections(
        'account_id' => account.id, 'agent_id' => agente[:id], 'connection_ids' => []
      )
      expect(vacio[:agent][:connection_ids]).to be_empty
    end

    it 'no permite robar el Hermes de otro agente' do
      otro_usuario = create(:user, account: account)
      agente1 = crear_agente(nombre: 'A1')
      agente2 = crear_agente(user: otro_usuario, nombre: 'A2')
      conn = crear_hermes(agente_id: agente1[:id])[:connection]

      expect do
        described_class.hermes_agents_set_connections(
          'account_id' => account.id, 'agent_id' => agente2[:id], 'connection_ids' => [conn[:id]]
        )
      end.to raise_error(/ya está ligado a otro agente/)
    end

    it 'rechaza un usuario que no pertenece a la cuenta' do
      ajeno = create(:user, account: other_account)

      expect { crear_agente(user: ajeno) }.to raise_error(/no pertenece a esta cuenta/)
    end

    # Ignorar un id inexistente dejaría al agente sin el Hermes que se creía haberle ligado.
    it 'rechaza ids de conexión inexistentes en vez de ignorarlos' do
      agente = crear_agente

      expect do
        described_class.hermes_agents_set_connections(
          'account_id' => account.id, 'agent_id' => agente[:id], 'connection_ids' => [999_999]
        )
      end.to raise_error(/conexiones no encontradas/)
    end

    it 'no alcanza un agente de otra cuenta' do
      ajeno = create(:user, account: other_account)
      agente_ajeno = described_class.hermes_agents_create(
        'account_id' => other_account.id, 'user_id' => ajeno.id, 'name' => 'Ajeno'
      )[:agent]

      expect do
        described_class.hermes_agents_update('account_id' => account.id, 'agent_id' => agente_ajeno[:id], 'name' => 'X')
      end.to raise_error(/no encontrado en esta cuenta/)
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
