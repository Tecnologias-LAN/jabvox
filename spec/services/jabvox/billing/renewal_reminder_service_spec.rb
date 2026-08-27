# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Billing::RenewalReminderService do
  include ActiveJob::TestHelper

  let(:plan) { create(:jabvox_plan) }
  let(:now) { Time.zone.parse('2026-08-11 12:00') }

  def account_expiring_in(days)
    account = create(:account)
    create(:user, :administrator, account: account, email: "admin#{days}@x.com")
    account.update!(jabvox_plan_id: plan.id, jabvox_plan_expires_at: now + days.days)
    account
  end

  it 'envía recordatorio a cuentas que vencen en 7, 3 y 1 días' do
    account_expiring_in(7)
    account_expiring_in(3)
    account_expiring_in(1)

    expect { described_class.new.call(now: now) }
      .to have_enqueued_mail(Jabvox::Billing::RenewalMailer, :reminder).exactly(3).times
  end

  it 'no envía a cuentas que vencen en un día fuera de la ventana (p.ej. 5 días)' do
    account_expiring_in(5)
    expect { described_class.new.call(now: now) }
      .not_to have_enqueued_mail(Jabvox::Billing::RenewalMailer, :reminder)
  end

  it 'es idempotente por día: no reenvía si ya se avisó hoy' do
    account_expiring_in(3)
    perform_enqueued_jobs { described_class.new.call(now: now) }
    expect { described_class.new.call(now: now) }
      .not_to have_enqueued_mail(Jabvox::Billing::RenewalMailer, :reminder)
  end

  it 'no toca cuentas sin plan asignado' do
    create(:account) # sin jabvox_plan_id
    expect { described_class.new.call(now: now) }
      .not_to have_enqueued_mail(Jabvox::Billing::RenewalMailer, :reminder)
  end
end
