require 'rails_helper'

RSpec.describe Jabvox::WhatsappFlows::SubmissionRecorder do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox, meta_flow_id: 'meta-flow-1', status: 'published', meta_status: 'PUBLISHED') }

  def outgoing_message_with_flow_token(token, meta_flow_id: 'meta-flow-1')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                      additional_attributes: {
                        'template_params' => {
                          'name' => 'plantilla_flow',
                          'processed_params' => {
                            'buttons' => [{ 'type' => 'flow', 'flow_token' => token, 'flow_id' => meta_flow_id }]
                          }
                        }
                      })
  end

  def incoming_reply_message(answers)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                      content_attributes: { 'whatsapp_flow_response' => answers })
  end

  it 'creates a submission and one answer per response field when the flow_token matches a known send' do
    flow
    token = 'tok-abc'
    outgoing_message_with_flow_token(token)
    incoming = incoming_reply_message({ 'flow_token' => token, 'calificacion' => 'Excelente' })

    submission = described_class.new(account).record(incoming)

    expect(submission).to be_a(JabvoxWhatsappFlowSubmission)
    expect(submission.jabvox_whatsapp_flow_id).to eq(flow.id)
    expect(submission.flow_token).to eq(token)
    expect(submission.contact_id).to eq(contact.id)
    expect(submission.answers.count).to eq(1)
    expect(submission.answers.first.component_name).to eq('calificacion')
    expect(submission.answers.first.value_text).to eq('Excelente')
  end

  it 'resolves screen_id/component_id/component_type from the flow definition for a known field name' do
    flow
    token = 'tok-def'
    outgoing_message_with_flow_token(token)
    incoming = incoming_reply_message({ 'flow_token' => token, 'calificacion' => 'Bueno' })

    submission = described_class.new(account).record(incoming)
    answer = submission.answers.first
    expect(answer.screen_id).to eq('rating')
    expect(answer.component_id).to eq('cmp_3')
    expect(answer.component_type).to eq('RadioButtonsGroup')
  end

  it 'degrades gracefully (returns nil, creates nothing, never raises) when the flow_token has no matching outgoing send' do
    incoming = incoming_reply_message({ 'flow_token' => 'never-sent-by-jabvox' })

    expect do
      result = described_class.new(account).record(incoming)
      expect(result).to be_nil
    end.not_to change(JabvoxWhatsappFlowSubmission, :count)
  end

  it 'degrades gracefully when there is no whatsapp_flow_response at all' do
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

    expect(described_class.new(account).record(incoming)).to be_nil
  end

  it 'degrades gracefully when the outgoing button flow_id does not match any catalogued JabvoxWhatsappFlow' do
    token = 'tok-orphan'
    outgoing_message_with_flow_token(token, meta_flow_id: 'some-other-meta-flow-id')
    incoming = incoming_reply_message({ 'flow_token' => token })

    expect(described_class.new(account).record(incoming)).to be_nil
  end

  it 'is idempotent: replaying the same flow_token does not create a second submission' do
    flow
    token = 'tok-repeat'
    outgoing_message_with_flow_token(token)
    incoming = incoming_reply_message({ 'flow_token' => token, 'calificacion' => 'Excelente' })

    first = described_class.new(account).record(incoming)
    expect(first).to be_a(JabvoxWhatsappFlowSubmission)

    expect do
      described_class.new(account).record(incoming)
    end.not_to change(JabvoxWhatsappFlowSubmission, :count)
  end

  it 'never raises even if something unexpected happens while resolving' do
    flow
    token = 'tok-boom'
    outgoing_message_with_flow_token(token)
    incoming = incoming_reply_message({ 'flow_token' => token, 'calificacion' => 'Excelente' })
    allow_any_instance_of(described_class).to receive(:create_submission).and_raise(StandardError, 'boom')

    expect { described_class.new(account).record(incoming) }.not_to raise_error
  end
end
