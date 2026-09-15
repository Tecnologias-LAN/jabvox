# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      expect(account_user.user.notification_settings).not_to be_nil

      expect(account_user.user.notification_settings.first.email_conversation_creation?).to be(false)
      expect(account_user.user.notification_settings.first.email_conversation_assignment?).to be(true)
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end

  describe 'filtered unread count invalidation' do
    let(:account) { create(:account) }
    let(:user) { create(:user) }
    let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, user_visibility_changed!: true) }

    before do
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'invalidates filtered counts when the user is added to an account' do
      create(:account_user, account: account, user: user)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
    end

    it 'invalidates filtered counts when the user role changes' do
      account_user = create(:account_user, account: account, user: user)

      account_user.update!(role: :administrator)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id).twice
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        'account.cache_invalidated',
        kind_of(Time),
        account: account,
        cache_keys: account.cache_keys
      )
    end

    it 'invalidates filtered counts when the user is removed from an account' do
      account_user = create(:account_user, account: account, user: user)

      account_user.destroy!

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id).twice
    end
  end

  describe 'seguridad: resincronización de permisos de Hermes al cambiar de rol' do
    let(:account) { create(:account) }
    let(:user) { create(:user) }
    let(:custom_role) { create(:custom_role, account: account, permissions: []) }

    # JabvoxHermesUserPermission#permissions_for_role deriva TODO (read/create/write/
    # execute/configure) para un administrator?, sin mirar el custom role. Esa tabla se
    # escribe una sola vez (sync_from_role!) y no se releía en cada request — quedaba
    # obsoleta si el rol cambiaba después. Sin este callback, degradar a un admin a un
    # rol personalizado restrictivo dejaba su fila de permisos de Hermes con los
    # privilegios amplios de cuando era admin.
    it 'downgrades stale Hermes permissions when an admin is restricted to a custom role' do
      account_user = create(:account_user, account: account, user: user, role: :administrator)
      JabvoxHermesUserPermission.sync_from_role!(account.id, user.id)
      expect(JabvoxHermesUserPermission.granted_for(account.id, user.id)).to include('execute', 'configure')

      account_user.update!(role: :agent, custom_role_id: custom_role.id)

      expect(JabvoxHermesUserPermission.granted_for(account.id, user.id)).to eq(['read'])
    end

    it 'upgrades Hermes permissions when a restricted user is promoted to administrator' do
      account_user = create(:account_user, account: account, user: user, role: :agent, custom_role_id: custom_role.id)
      JabvoxHermesUserPermission.sync_from_role!(account.id, user.id)
      expect(JabvoxHermesUserPermission.granted_for(account.id, user.id)).to eq(['read'])

      account_user.update!(role: :administrator, custom_role_id: nil)

      expect(JabvoxHermesUserPermission.granted_for(account.id, user.id)).to include('execute', 'configure')
    end

    it 'does not resync when an unrelated attribute changes' do
      account_user = create(:account_user, account: account, user: user, role: :agent)
      JabvoxHermesUserPermission.sync_from_role!(account.id, user.id)

      expect(JabvoxHermesUserPermission).not_to receive(:sync_from_role!)
      account_user.update!(availability: :busy)
    end
  end
end
