require 'rails_helper'
RSpec.describe 'WhatsApp group webhook events', type: :model do
  let(:account) { create(:account, jabvox_whatsapp_groups_enabled_jabvox: true) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let!(:group) do
    JabvoxWhatsappGroup.create!(account: account, inbox: inbox, name_jabvox: 'Sala', status_jabvox: 'active', provider_group_id_jabvox: 'g123')
  end

  def dispatch(field, value)
    Jabvox::Whatsapp::IncomingGroupEventService.new(channel: channel, field: field, value: value).perform
  end

  it 'joins, promotes, updates metadata/status and leaves via webhook events' do
    dispatch('group_participants_update', { group_id: 'g123', participants: [{ phone_number: '573001112233', action: 'join' }] })
    m = group.members.find_by(phone_number_jabvox: '573001112233')
    expect(m).to be_present
    expect(m.invite_status_jabvox).to eq('joined')

    dispatch('group_participants_update', { group_id: 'g123', participants: [{ phone_number: '573001112233', action: 'promote' }] })
    expect(m.reload.role_jabvox).to eq('admin')

    dispatch('group_settings_update', { group_id: 'g123', subject: 'Sala VIP' })
    expect(group.reload.name_jabvox).to eq('Sala VIP')

    dispatch('group_status_update', { group_id: 'g123', status: 'archived' })
    expect(group.reload.status_jabvox).to eq('archived')

    dispatch('group_participants_update', { group_id: 'g123', participants: [{ phone_number: '573001112233', action: 'leave' }] })
    expect(m.reload.invite_status_jabvox).to eq('left')
  end

  it 'ignores events for an unknown group id' do
    expect { dispatch('group_participants_update', { group_id: 'unknown', participants: [{ phone_number: '1', action: 'join' }] }) }
      .not_to change(JabvoxWhatsappGroupMember, :count)
  end
end
