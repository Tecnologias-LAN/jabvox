require 'rails_helper'

RSpec.describe Jabvox::Tickets::DefaultCategoriesService do
  let(:account) { create(:account) }

  describe '#call' do
    it 'siembra las categorías por defecto en la cuenta' do
      expect { described_class.new(account).call }
        .to change { account.jabvox_ticket_categories.count }
        .from(0).to(described_class::DEFAULTS.size)
    end

    it 'crea las categorías activas con SLA y tipo definidos' do
      described_class.new(account).call
      category = account.jabvox_ticket_categories.find_by(name_jabvox: 'Falla técnica')

      expect(category).to have_attributes(
        active_jabvox: true,
        category_type_jabvox: 'incident',
        sla_response_minutes_jabvox: 30
      )
    end

    it 'es idempotente: no duplica categorías al ejecutarse de nuevo' do
      described_class.new(account).call

      expect { described_class.new(account).call }
        .not_to(change { account.jabvox_ticket_categories.count })
    end

    it 'no pisa una categoría existente con el mismo nombre' do
      create(:jabvox_ticket_category, account: account, name_jabvox: 'Falla técnica',
                                      sla_response_minutes_jabvox: 999)
      described_class.new(account).call

      matches = account.jabvox_ticket_categories.where(name_jabvox: 'Falla técnica')
      expect(matches.count).to eq(1)
      expect(matches.first.sla_response_minutes_jabvox).to eq(999)
    end
  end
end
