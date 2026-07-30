require 'rails_helper'
RSpec.describe 'WhatsApp Groups model layer', type: :model do
  let(:account) { create(:account, jabvox_whatsapp_groups_enabled_jabvox: true) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  it 'gates eligibility per Meta rules and enforces the 8-member cap', :aggregate_failures do
    expect(account.feature_enabled?('jabvox_whatsapp_groups')).to be true

    # cloud but not OBA -> ineligible with reason
    expect(channel.whatsapp_groups_supported?).to be false
    expect(channel.whatsapp_groups_ineligibility_reason).to eq('not_official_business')

    channel.provider_config['is_official_business_account'] = true
    channel.save!(validate: false)
    expect(channel.reload.whatsapp_groups_supported?).to be true
    expect(channel.whatsapp_groups_enabled?).to be true

    channel.provider_config['source'] = 'coexistence'
    channel.save!(validate: false)
    expect(channel.reload.whatsapp_groups_ineligibility_reason).to eq('coexistence')
    channel.provider_config['source'] = nil
    channel.save!(validate: false)

    group = JabvoxWhatsappGroup.create!(account: account, inbox: inbox, name_jabvox: 'Sala', status_jabvox: 'active')
    8.times { |i| group.members.create!(account: account, phone_number_jabvox: "57300111220#{i}", invite_status_jabvox: 'joined') }
    expect(group.reload.active_members_count).to eq(8)

    ninth = group.members.build(account: account, phone_number_jabvox: '573009998888', invite_status_jabvox: 'joined')
    expect(ninth.valid?).to be false
    expect(ninth.errors.full_messages.join).to match(/8 active members/)
  end
end
