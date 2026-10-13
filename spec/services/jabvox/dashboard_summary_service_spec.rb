# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::DashboardSummaryService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:date_range) do
    Jabvox::DashboardDateRange.new(
      account: account,
      date_from: Time.current.to_date.iso8601,
      date_to: Time.current.to_date.iso8601
    )
  end

  describe 'aislamiento por cuenta en tickets' do
    # El policy_scope de tickets puede traer tickets de OTRAS cuentas cuando el
    # usuario es staff del helpdesk central. El panel es por cuenta: NUNCA debe
    # contar tickets ajenos. Simulamos ese caso pasando un ticket_scope global.
    it 'no cuenta tickets de otra cuenta aunque el scope los incluya' do
      create(:jabvox_ticket, account: account, status_jabvox: :new_ticket)
      # Dos tickets pendientes de OTRA cuenta (el bug reportado: aparecían en el panel).
      create(:jabvox_ticket, account: other_account, status_jabvox: :new_ticket)
      create(:jabvox_ticket, account: other_account, status_jabvox: :assigned)

      # ticket_scope "global" (como lo entrega el policy_scope de un staff del helpdesk).
      global_scope = JabvoxTicket.kept

      result = described_class.new(
        account: account,
        date_range: date_range,
        modules: [:tickets],
        ticket_scope: global_scope
      ).call

      # Solo el ticket de la cuenta del panel se cuenta como pendiente.
      expect(result[:modules][:tickets][:pending]).to eq(1)
    end

    it 'no cuenta como creados los tickets de otra cuenta en el período' do
      # created_at dentro del rango del panel, independiente de la hora del test.
      inside = date_range.from + 1.hour
      create(:jabvox_ticket, account: account, status_jabvox: :new_ticket, created_at: inside)
      create(:jabvox_ticket, account: other_account, status_jabvox: :new_ticket, created_at: inside)

      result = described_class.new(
        account: account,
        date_range: date_range,
        modules: [:tickets],
        ticket_scope: JabvoxTicket.kept
      ).call

      expect(result[:modules][:tickets][:created]).to eq(1)
    end
  end
end
