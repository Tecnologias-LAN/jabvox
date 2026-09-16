require 'rails_helper'

RSpec.describe JabvoxWhatsappFlow, type: :model do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  def build_flow(attrs = {})
    account.jabvox_whatsapp_flows.new({
      inbox: inbox, waba_id: '123456789', name: 'Encuesta', category: 'SURVEY'
    }.merge(attrs))
  end

  it 'is valid with the minimal required attributes' do
    flow = build_flow
    expect(flow).to be_valid
  end

  it 'requires a name' do
    flow = build_flow(name: '')
    expect(flow).not_to be_valid
    expect(flow.errors[:name]).to be_present
  end

  it 'requires a category from the fixed Meta list' do
    flow = build_flow(category: 'NOT_A_CATEGORY')
    expect(flow).not_to be_valid
    expect(flow.errors[:category]).to be_present
  end

  it 'requires a waba_id' do
    flow = build_flow(waba_id: nil)
    expect(flow).not_to be_valid
  end

  it 'defaults to draft status' do
    flow = build_flow
    flow.save!
    expect(flow.status).to eq('draft')
  end

  it 'rejects an unknown local status' do
    flow = build_flow(status: 'bogus')
    expect(flow).not_to be_valid
  end

  it 'rejects an unknown meta_status but allows nil' do
    flow = build_flow
    flow.meta_status = nil
    expect(flow).to be_valid
    flow.meta_status = 'BOGUS'
    expect(flow).not_to be_valid
  end

  describe '#published_on_meta?' do
    it 'is true only when meta_status mirrors PUBLISHED' do
      flow = build_flow(meta_status: 'DRAFT')
      expect(flow.published_on_meta?).to be false
      flow.meta_status = 'PUBLISHED'
      expect(flow.published_on_meta?).to be true
    end
  end

  describe 'account scoping' do
    it 'is only visible through its own account association' do
      mine = create(:jabvox_whatsapp_flow, account: account, inbox: inbox)
      other_channel = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      other_inbox = create(:inbox, account: other_account, channel: other_channel)
      create(:jabvox_whatsapp_flow, account: other_account, inbox: other_inbox)

      expect(account.jabvox_whatsapp_flows).to contain_exactly(mine)
    end
  end

  describe 'scopes' do
    it 'by_category filters, and returns everything when blank' do
      a = create(:jabvox_whatsapp_flow, account: account, inbox: inbox, category: 'SURVEY')
      b = create(:jabvox_whatsapp_flow, account: account, inbox: inbox, category: 'LEAD_GENERATION')

      expect(account.jabvox_whatsapp_flows.by_category('SURVEY')).to contain_exactly(a)
      expect(account.jabvox_whatsapp_flows.by_category(nil)).to contain_exactly(a, b)
    end
  end
end
