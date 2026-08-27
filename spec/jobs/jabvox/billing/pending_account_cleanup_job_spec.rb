# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Billing::PendingAccountCleanupJob, type: :job do
  # Usa el singleton (first_or_create!) para que coincida con lo que lee el job
  # (JabvoxBillingConfig.instance). Crear un registro suelto podría no ser el que
  # el job resuelve como "el primero".
  let!(:billing_config) do
    JabvoxBillingConfig.instance.tap { |c| c.update!(unpaid_account_cleanup_days: 7) }
  end

  describe '#perform' do
    context 'con cuentas sin pago fuera del periodo de gracia' do
      let!(:old_pending_account) do
        create(:account, status: :payment_pending, created_at: 8.days.ago)
      end

      it 'elimina la cuenta' do
        expect do
          described_class.new.perform
        end.to change(Account, :count).by(-1)
      end

      it 'elimina los usuarios de la cuenta' do
        # User se asocia a Account vía account_users, no con `account:` directo.
        user = create(:user)
        create(:account_user, account: old_pending_account, user: user)
        expect do
          described_class.new.perform
        end.to change(User, :count).by(-1)
      end

      it 'registra log de eliminación' do
        allow(Rails.logger).to receive(:info)
        described_class.new.perform
        expect(Rails.logger).to have_received(:info).with(
          match(/Eliminando cuenta #{old_pending_account.id}/)
        )
      end
    end

    context 'con cuentas dentro del periodo de gracia' do
      let!(:recent_pending_account) do
        create(:account, status: :payment_pending, created_at: 5.days.ago)
      end

      it 'no elimina la cuenta' do
        expect do
          described_class.new.perform
        end.not_to change(Account, :count)
      end
    end

    context 'con cuentas que tienen transacción aprobada' do
      let!(:paid_account) do
        create(:account, status: :payment_pending, created_at: 10.days.ago)
      end

      let!(:transaction) do
        create(:jabvox_provisioning_transaction,
               account: paid_account,
               status: :payment_approved)
      end

      it 'no elimina la cuenta aunque esté fuera del periodo' do
        expect do
          described_class.new.perform
        end.not_to change(Account, :count)
      end
    end

    context 'con cuentas activas o suspendidas' do
      let!(:active_account) do
        create(:account, status: :active, created_at: 10.days.ago)
      end

      let!(:suspended_account) do
        create(:account, status: :suspended, created_at: 10.days.ago)
      end

      it 'no elimina cuentas que no estén en payment_pending' do
        expect do
          described_class.new.perform
        end.not_to change(Account, :count)
      end
    end

    context 'cuando falla la eliminación de una cuenta' do
      let!(:account1) do
        create(:account, status: :payment_pending, created_at: 8.days.ago)
      end

      let!(:account2) do
        create(:account, status: :payment_pending, created_at: 8.days.ago)
      end

      before do
        # find_each recarga instancias nuevas, así que el stub debe ir sobre any_instance
        # y decidir por id: la primera cuenta falla, la segunda se elimina normal.
        failing_id = account1.id
        allow_any_instance_of(Account).to receive(:destroy!).and_wrap_original do |method, *args|
          raise StandardError, 'Test error' if method.receiver.id == failing_id

          method.call(*args)
        end
      end

      it 'continúa con las demás cuentas' do
        allow(Rails.logger).to receive(:error)
        expect do
          described_class.new.perform
        end.to change(Account, :count).by(-1)
      end

      it 'registra el error en logs' do
        allow(Rails.logger).to receive(:error)
        described_class.new.perform
        expect(Rails.logger).to have_received(:error).with(
          match(/Error eliminando cuenta/)
        )
      end
    end

    context 'configuración de días de gracia' do
      before do
        billing_config.update!(unpaid_account_cleanup_days: 3)
      end

      let!(:account_4_days) do
        create(:account, status: :payment_pending, created_at: 4.days.ago)
      end

      let!(:account_2_days) do
        create(:account, status: :payment_pending, created_at: 2.days.ago)
      end

      it 'respeta la configuración personalizada' do
        expect do
          described_class.new.perform
        end.to change(Account, :count).by(-1)

        expect(Account.exists?(account_4_days.id)).to be false
        expect(Account.exists?(account_2_days.id)).to be true
      end
    end
  end
end
