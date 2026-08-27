# frozen_string_literal: true

require 'rails_helper'

# Cuotas por cuenta que BLOQUEAN la creación (reglas de automatización, dashboards de
# analytics, documentos de IA). El límite vive en accounts.limits; nil/ausente = ilimitado.
RSpec.describe Jabvox::AccountResourceLimit do
  let(:account) { create(:account, limits: limits) }

  describe 'automation_rules' do
    let(:limits) { { 'automation_rules' => 1 } }

    it 'permite crear hasta el límite y bloquea el siguiente' do
      create(:automation_rule, account: account)
      expect { create(:automation_rule, account: account) }
        .to raise_error(described_class::LimitExceeded, /automation_rules/)
    end
  end

  describe 'analytics_dashboards' do
    let(:limits) { { 'analytics_dashboards' => 1 } }

    it 'bloquea al superar el tope' do
      create(:jabvox_analytics_dashboard, account: account)
      expect { create(:jabvox_analytics_dashboard, account: account) }
        .to raise_error(described_class::LimitExceeded, /analytics_dashboards/)
    end
  end

  describe 'ai_documents (ai_chat + response_bot suman al mismo tope)' do
    let(:limits) { { 'ai_documents' => 2 } }

    it 'cuenta ambos tipos contra el mismo límite' do
      create(:jabvox_ai_chat_document, account: account)
      create(:jabvox_response_bot_document, account: account)
      # ya van 2 (uno de cada tipo) → el tercero de cualquier tipo se bloquea
      expect { create(:jabvox_ai_chat_document, account: account) }
        .to raise_error(described_class::LimitExceeded, /ai_documents/)
    end
  end

  describe 'sin límite configurado' do
    let(:limits) { {} }

    it 'no bloquea (ilimitado)' do
      expect { create_list(:automation_rule, 3, account: account) }.not_to raise_error
    end
  end

  describe 'inboxes' do
    let(:limits) { { 'inboxes' => 1 } }

    it 'bloquea nuevas bandejas cuando se alcanza el límite' do
      create(:inbox, account: account)

      expect { create(:inbox, account: account) }
        .to raise_error(described_class::LimitExceeded, /inboxes/)
    end
  end
end
