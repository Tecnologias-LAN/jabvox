# frozen_string_literal: true

require 'rails_helper'

# API de flujos: gateo por módulo, aislamiento entre cuentas y el ciclo completo
# de guardar el grafo, validarlo, activar y ejecutar.
RSpec.describe 'Jabvox flows API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }

  before { account.update!(jabvox_advanced_automations_enabled_jabvox: true) }

  def url(path = '') = "/api/v1/accounts/#{account.id}/jabvox/flows#{path}"

  # Grafo mínimo VÁLIDO: disparador manual → condición configurada.
  def valid_graph
    { nodes: [
        { id: 't1', type: 'trigger.manual', data: { nodeType: 'trigger.manual' } },
        { id: 'n1', type: 'logic.if', data: { nodeType: 'logic.if' },
          params: { left: '{{trigger.valor}}', operator: 'equals', right: 'si' } }
      ],
      edges: [{ id: 'e1', source: 't1', target: 'n1' }] }
  end

  def create_flow(name: 'Flujo')
    post url, params: { name: name }, headers: headers, as: :json
    response.parsed_body['id']
  end

  def save_graph(id, graph = valid_graph)
    put url("/#{id}/versions"), params: graph, headers: headers, as: :json
  end

  describe 'gateo por módulo' do
    it 'responde 403 en TODA la API con el módulo apagado' do
      account.update!(jabvox_advanced_automations_enabled_jabvox: false)

      get url, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      get url('/nodes'), headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post url, params: { name: 'x' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'aislamiento entre cuentas' do
    let(:other_account) { create(:account) }

    it 'no deja ver un flujo de otra cuenta ni siquiera con el módulo activo' do
      other_account.update!(jabvox_advanced_automations_enabled_jabvox: true)
      foreign = JabvoxFlow.create!(account: other_account, name: 'Ajeno')

      get url("/#{foreign.id}"), headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'no lista flujos de otras cuentas' do
      JabvoxFlow.create!(account: other_account, name: 'Ajeno')
      create_flow(name: 'Propio')

      get url, headers: headers, as: :json

      expect(response.parsed_body.pluck('name')).to eq(['Propio'])
    end
  end

  describe 'CRUD' do
    it 'crea, actualiza y borra un flujo' do
      id = create_flow(name: 'Mi flujo')
      expect(response).to have_http_status(:created)

      patch url("/#{id}"), params: { name: 'Renombrado' }, headers: headers, as: :json
      expect(response.parsed_body['name']).to eq('Renombrado')

      delete url("/#{id}"), headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'se niega a borrar un flujo ACTIVO' do
      id = create_flow
      save_graph(id)
      patch url("/#{id}"), params: { status: 'active' }, headers: headers, as: :json

      delete url("/#{id}"), headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
    end

    it 'duplica un flujo con su grafo' do
      id = create_flow
      save_graph(id)

      post url("/#{id}/duplicate"), headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['name']).to eq('Flujo (copia)')
      expect(response.parsed_body.dig('currentVersion', 'graph', 'nodes').size).to eq(2)
    end
  end

  describe 'validación del grafo' do
    it 'GUARDA un grafo incompleto: el editor autoguarda mientras se construye' do
      id = create_flow
      incompleto = { nodes: [{ id: 'n1', type: 'logic.if', params: {} }], edges: [] }

      save_graph(id, incompleto)

      expect(response).to have_http_status(:ok)
    end

    it 'RECHAZA guardar un grafo estructuralmente roto' do
      id = create_flow
      roto = { nodes: [{ id: 'n1', type: 'tipo.inventado' }], edges: [] }

      save_graph(id, roto)

      expect(response).to have_http_status(:unprocessable_entity)
      codes = response.parsed_body.dig('validation', 'issues').pluck('code')
      expect(codes).to include('NODE_UNKNOWN_TYPE')
    end

    it 'informa de los obligatorios vacíos en modo estricto sin fallar' do
      id = create_flow
      save_graph(id, { nodes: [{ id: 'n1', type: 'logic.if', params: {} }], edges: [] })

      post url("/#{id}/validate"), params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['valid']).to be(false)
      expect(response.parsed_body['issues'].pluck('code')).to include('PARAM_REQUIRED_EMPTY')
    end

    it 'NO deja activar un flujo cuyo grafo no pasa la validación estricta' do
      id = create_flow
      save_graph(id, { nodes: [{ id: 'n1', type: 'logic.if', params: {} }], edges: [] })

      patch url("/#{id}"), params: { status: 'active' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JabvoxFlow.find(id)).not_to be_active
    end

    it 'activa un flujo cuyo grafo es válido' do
      id = create_flow
      save_graph(id)

      patch url("/#{id}"), params: { status: 'active' }, headers: headers, as: :json

      expect(response.parsed_body['status']).to eq('active')
    end
  end

  describe 'versionado' do
    it 'cada guardado crea una versión NUEVA y restaurar avanza el historial' do
      id = create_flow
      save_graph(id)
      save_graph(id, { nodes: [], edges: [] })

      get url("/#{id}/versions"), headers: headers, as: :json
      expect(response.parsed_body.pluck('version')).to eq([2, 1])

      post url("/#{id}/versions/1/restore"), headers: headers, as: :json
      expect(response.parsed_body['version']).to eq(3)
      expect(response.parsed_body.dig('graph', 'nodes').size).to eq(2)
    end
  end

  # Las notas adhesivas son DECORACIÓN: se guardan con el grafo y vuelven al
  # cargar, pero ni la validación ni el motor las miran.
  describe 'notas adhesivas' do
    def graph_with_notes
      valid_graph.merge(notes: [
                          { id: 'note1', position: { x: 40, y: 60 },
                            width: 260, height: 160, color: 'amber',
                            text: 'Ojo: revisar el horario' }
                        ])
    end

    it 'guarda las notas y las devuelve al cargar el flujo' do
      id = create_flow
      save_graph(id, graph_with_notes)

      expect(response).to have_http_status(:ok)

      get url("/#{id}"), headers: headers, as: :json
      notes = response.parsed_body.dig('currentVersion', 'graph', 'notes')
      expect(notes.size).to eq(1)
      expect(notes.first['text']).to eq('Ojo: revisar el horario')
      expect(notes.first['width']).to eq(260)
    end

    it 'devuelve `notes` vacío cuando el grafo se guardó sin notas' do
      id = create_flow
      save_graph(id)

      get url("/#{id}"), headers: headers, as: :json
      expect(response.parsed_body.dig('currentVersion', 'graph', 'notes')).to eq([])
    end

    it 'la validación IGNORA las notas: no cuentan como pasos ni piden disparador' do
      id = create_flow
      save_graph(id, { nodes: [], edges: [],
                       notes: [{ id: 'note1', text: 'nota sola' }] })

      expect(response).to have_http_status(:ok)

      # Un lienzo con SOLO notas se valida igual que uno vacío: si las notas se
      # tomaran por pasos, aquí saltaría FLOW_NO_TRIGGER.
      post url("/#{id}/validate"), params: {}, headers: headers, as: :json
      expect(response.parsed_body['issues']).to eq([])
      expect(response.parsed_body.dig('validation', 'issues')).to be_nil
    end

    it 'una nota con el id de un paso NO provoca id duplicado' do
      id = create_flow
      save_graph(id, valid_graph.merge(notes: [{ id: 't1', text: 'mismo id que el disparador' }]))

      expect(response).to have_http_status(:ok)

      post url("/#{id}/validate"), params: {}, headers: headers, as: :json
      expect(response.parsed_body['issues'].pluck('code')).not_to include('NODE_DUPLICATE_ID')
      expect(response.parsed_body['valid']).to be(true)
    end

    it 'una nota con texto absurdo NO bloquea el guardado ni la activación' do
      id = create_flow
      save_graph(id, graph_with_notes)

      patch url("/#{id}"), params: { status: 'active' }, headers: headers, as: :json

      expect(response.parsed_body['status']).to eq('active')
    end

    it 'duplicar el flujo se lleva las notas' do
      id = create_flow
      save_graph(id, graph_with_notes)

      post url("/#{id}/duplicate"), headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('currentVersion', 'graph', 'notes').size).to eq(1)
    end
  end

  describe 'ejecución' do
    it 'encola una ejecución manual' do
      id = create_flow
      save_graph(id)

      post url("/#{id}/run"), params: { payload: { valor: 'si' } }, headers: headers, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['status']).to eq('pending')
    end

    it 'prueba UN paso y devuelve su salida ya resuelta' do
      id = create_flow
      save_graph(id)

      post url("/#{id}/run_node"), params: { nodeId: 'n1', payload: { valor: 'si' } },
                                   headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('success')
      expect(response.parsed_body.dig('output', 'matched')).to be(true)
    end

    it 'responde 404 al probar un paso que no está en el grafo' do
      id = create_flow
      save_graph(id)

      post url("/#{id}/run_node"), params: { nodeId: 'fantasma' }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'catálogo y opciones' do
    it 'sirve el catálogo completo con los params de cada tipo' do
      get url('/nodes'), headers: headers, as: :json

      nodes = response.parsed_body['nodes']
      expect(nodes.size).to eq(Jabvox::Flows::Registry::ALL.size)
      expect(nodes.find { |n| n['type'] == 'logic.if' }['params'].pluck('key'))
        .to include('left', 'operator', 'right')
    end

    it 'rechaza un kind de opciones desconocido' do
      get url('/options/no_existe'), headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'exige la dependencia declarada por el catálogo' do
      get url('/options/kanban_stages'), headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to include('funnelId')
    end
  end
end
