# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser, type: :model do
  describe 'associations' do
    # option and dependant nullify
    it { is_expected.to belong_to(:custom_role).optional }
  end

  describe 'permissions' do
    context 'when custom role is assigned' do
      it 'returns the custom role permissions plus the `custom_role` marker and the base role' do
        account = create(:account)
        custom_role = create(:custom_role, account: account)
        account_user = create(:account_user, account: account, role: :agent, custom_role: custom_role)

        # The base role ('agent') is included so a custom role that grants only
        # granular permissions can still reach the agent-level base routes
        # (avoids the router redirect-loop that blanked the app).
        expect(account_user.permissions).to match_array(custom_role.permissions + %w[custom_role agent])
      end

      it 'includes the administrator base role for an admin with a custom role' do
        account = create(:account)
        custom_role = create(:custom_role, account: account)
        account_user = create(:account_user, account: account, role: :administrator, custom_role: custom_role)

        expect(account_user.permissions).to match_array(custom_role.permissions + %w[custom_role administrator])
      end
    end

    context 'when custom role is not assigned' do
      it 'returns permissions of the default role' do
        account = create(:account)
        account_user = create(:account_user, account: account)

        expect(account_user.permissions).to eq([account_user.role])
      end
    end
  end

  describe 'filtered unread count invalidation' do
    it 'invalidates filtered counts when the custom role assignment changes' do
      account = create(:account)
      user = create(:user)
      account_user = create(:account_user, account: account, user: user)
      custom_role = create(:custom_role, account: account)
      invalidator = instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, user_visibility_changed!: true)

      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      account_user.update!(custom_role_id: custom_role.id)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        'account.cache_invalidated',
        kind_of(Time),
        account: account,
        cache_keys: account.cache_keys
      )
    end
  end

  describe 'audit log' do
    context 'when account user is created' do
      it 'has associated audit log created' do
        account_user = create(:account_user)
        account_user_audit_log = Audited::Audit.where(auditable_type: 'AccountUser', action: 'create').first
        expect(account_user_audit_log).to be_present
        expect(account_user_audit_log.associated).to eq(account_user.account)
      end
    end

    context 'when account user is updated' do
      it 'has associated audit log created' do
        account_user = create(:account_user)
        account_user.update!(availability: 'offline')
        account_user_audit_log = Audited::Audit.where(auditable_type: 'AccountUser', action: 'update').first
        expect(account_user_audit_log).to be_present
        expect(account_user_audit_log.associated).to eq(account_user.account)
        expect(account_user_audit_log.audited_changes).to eq('availability' => [0, 1])
      end
    end
  end
end
