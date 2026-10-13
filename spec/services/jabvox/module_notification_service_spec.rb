# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::ModuleNotificationService do
  describe '.create!' do
    let(:account) { create(:account, jabvox_internal_chat_enabled_jabvox: true) }
    let(:first_user) { create(:user, account: account) }
    let(:second_user) { create(:user, account: account) }
    let(:chat) do
      JabvoxInternalChat.create!(account: account, created_by: first_user, chat_type: :direct)
    end

    def create_notification(user, body: 'Mensaje inicial')
      described_class.create!(
        account: account,
        user: user,
        type: :jabvox_internal_chat_message,
        actor: chat,
        title: 'Chat de equipo',
        body: body,
        path: "/app/accounts/#{account.id}/jabvox/internal-chat"
      )
    end

    it 'creates a notification for each member receiving the same chat event' do
      create_notification(first_user)
      create_notification(second_user)

      expect(Notification.where(primary_actor: chat).pluck(:user_id)).to contain_exactly(
        first_user.id, second_user.id
      )
    end

    it 'refreshes the existing notification for the same actor and recipient' do
      notification = create_notification(first_user)
      notification.update!(read_at: Time.current)

      refreshed = create_notification(first_user, body: 'Mensaje nuevo')

      expect(refreshed.id).to eq(notification.id)
      expect(refreshed.reload.read_at).to be_nil
      expect(refreshed.meta['body']).to eq('Mensaje nuevo')
    end

    it 'does not create a notification when the module is disabled' do
      account.update!(jabvox_internal_chat_enabled_jabvox: false)

      expect(create_notification(first_user)).to be_nil
      expect(Notification.where(primary_actor: chat)).to be_empty
    end

    it 'rejects actors from another account and users outside the account' do
      foreign_account = create(:account, jabvox_internal_chat_enabled_jabvox: true)
      foreign_user = create(:user, account: foreign_account)
      foreign_chat = JabvoxInternalChat.create!(
        account: foreign_account,
        created_by: foreign_user,
        chat_type: :direct
      )

      expect do
        described_class.create!(
          account: account,
          user: first_user,
          type: :jabvox_internal_chat_message,
          actor: foreign_chat,
          title: 'Chat de equipo',
          body: 'Mensaje',
          path: "/app/accounts/#{account.id}/jabvox/internal-chat"
        )
      end.not_to change(Notification, :count)

      expect do
        create_notification(create(:user))
      end.not_to change(Notification, :count)
    end

    it 'only delivers AI balance notifications to account administrators' do
      account.update!(jabvox_ai_chat_enabled_jabvox: true)
      agent = create(:user, account: account)
      agent.account_users.find_by!(account: account).update!(role: :agent)
      movement = JabvoxAiBalanceMovement.create!(
        account: account,
        kind_jabvox: 'purchase',
        amount_cents_jabvox: 100
      )

      expect do
        described_class.create!(
          account: account,
          user: agent,
          type: :jabvox_ai_balance_movement,
          actor: movement,
          title: 'Movimiento en el saldo de IA',
          body: 'Saldo actualizado',
          path: "/app/accounts/#{account.id}/settings/jabvox/ai-budget"
        )
      end.not_to change(Notification, :count)
    end
  end
end
