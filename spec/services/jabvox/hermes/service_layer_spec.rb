# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::ServiceLayer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account, user: user) }

  describe 'guard contra DELETE' do
    it 'rechaza cualquier verbo DELETE con Forbidden' do
      expect { service.call(method: :delete, path: 'labels/1', params: { id: 1 }) }
        .to raise_error(described_class::Forbidden, /no está permitido/)
    end

    it 'rechaza DELETE aunque el path no exista en ROUTES' do
      expect { service.call(method: :delete, path: 'cualquier/cosa', params: {}) }
        .to raise_error(described_class::Forbidden)
    end

    it 'no expone ninguna ruta DELETE en ROUTES' do
      expect(described_class::ROUTES.keys.any? { |k| k.start_with?('DELETE') }).to be(false)
    end
  end

  describe 'acciones no destructivas (siguen funcionando)' do
    it 'crea una label scoped a la cuenta' do
      result = service.call(method: :post, path: 'labels', params: { title: 'vip' })
      expect(result[:title]).to eq('vip')
      expect(account.labels.find(result[:id])).to be_present
    end

    it 'lista labels de la cuenta' do
      account.labels.create!(title: 'soporte')
      result = service.call(method: :get, path: 'labels', params: {})
      expect(result.map { |l| l[:title] }).to include('soporte')
    end

    it 'rechaza un path no mapeado con UnknownAction' do
      expect { service.call(method: :get, path: 'usuarios', params: {}) }
        .to raise_error(described_class::UnknownAction)
    end
  end

  describe 'áreas de la cuenta (todo scoped a @account)' do
    it 'contactos: crea, busca y actualiza' do
      created = service.call(method: :post, path: 'contacts',
                             params: { name: 'Ana', email: 'ana@x.com', phone_number: '+571234' })
      expect(created[:name]).to eq('Ana')

      found = service.call(method: :get, path: 'contacts/search', params: { q: 'Ana' })
      expect(found.map { |c| c[:id] }).to include(created[:id])

      updated = service.call(method: :patch, path: "contacts/#{created[:id]}",
                             params: { id: created[:id], name: 'Ana María' })
      expect(updated[:name]).to eq('Ana María')
    end

    it 'notas de contacto: crea y lista' do
      contact = account.contacts.create!(name: 'Beto')
      note = service.call(method: :post, path: "contacts/#{contact.id}/notes",
                          params: { id: contact.id, content: 'llamar mañana' })
      expect(note[:content]).to eq('llamar mañana')
      listed = service.call(method: :get, path: "contacts/#{contact.id}/notes", params: { id: contact.id })
      expect(listed.map { |n| n[:content] }).to include('llamar mañana')
    end

    it 'gestiones: crea y actualiza management state' do
      st = service.call(method: :post, path: 'jabvox/management_states', params: { name: 'Contactado' })
      expect(st[:name]).to eq('Contactado')
      up = service.call(method: :patch, path: "jabvox/management_states/#{st[:id]}",
                        params: { id: st[:id], name: 'No contesta' })
      expect(up[:name]).to eq('No contesta')
    end

    it 'dialer: crea y lista campañas' do
      camp = service.call(method: :post, path: 'jabvox/dialer_campaigns', params: { name: 'Campaña Q3' })
      expect(camp[:name]).to eq('Campaña Q3')
      list = service.call(method: :get, path: 'jabvox/dialer_campaigns', params: {})
      expect(list.map { |c| c[:id] }).to include(camp[:id])
    end

    it 'inboxes: lista (solo lectura)' do
      expect { service.call(method: :get, path: 'inboxes', params: {}) }.not_to raise_error
    end

    it 'automatizaciones: crea y lista' do
      created = service.call(method: :post, path: 'automation_rules',
                             params: { name: 'Auto-etiqueta', event_name: 'conversation_created',
                                       conditions: [], actions: [] })
      expect(created[:name]).to eq('Auto-etiqueta')
      list = service.call(method: :get, path: 'automation_rules', params: {})
      expect(list.map { |r| r[:id] }).to include(created[:id])
    end
  end

  describe 'Hermes responde bandejas por WEBHOOK directo (no AgentBot)' do
    before { create(:jabvox_context_forge_handoff, :ready, account: account, hermes_url: 'http://10.147.0.49:8642') }

    let(:inbox) { create(:inbox, account: account) }

    it 'crea el webhook message_created apuntando SIEMPRE al Hermes de la cuenta' do
      hook = service.call(method: :post, path: 'webhooks', params: {})
      expect(hook[:url]).to eq('http://10.147.0.49:8642') # fijado por Jabvox, no por el LLM
      expect(hook[:subscriptions]).to include('message_created')
      expect(hook[:webhook_type]).to eq('account_type')
    end

    it 'crea el webhook para UNA bandeja concreta (inbox_type)' do
      hook = service.call(method: :post, path: 'webhooks/inbox', params: { inbox_id: inbox.id })
      expect(hook[:inbox_id]).to eq(inbox.id)
      expect(hook[:webhook_type]).to eq('inbox_type')
    end

    it 'es idempotente: repetir no duplica el webhook' do
      service.call(method: :post, path: 'webhooks', params: {})
      expect { service.call(method: :post, path: 'webhooks', params: {}) }
        .not_to change(account.webhooks, :count)
    end

    it 'sin Hermes conectado, crear el webhook falla (no inventa URL)' do
      account.jabvox_context_forge_handoff.update!(hermes_url: nil, status: 'pending')
      expect { service.call(method: :post, path: 'webhooks', params: {}) }
        .to raise_error(described_class::UnknownAction, /sin hermes_url/)
    end
  end
end
