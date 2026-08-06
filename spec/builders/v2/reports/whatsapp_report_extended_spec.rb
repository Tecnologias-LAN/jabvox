require 'rails_helper'
RSpec.describe 'WhatsApp report extended metrics', type: :model do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:ci) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci, assignee: agent) }

  def builder(params = {})
    V2::Reports::WhatsappAgentReportBuilder.new(account: account, params: params)
  end

  # Bug: el reporte filtraba por created_at de la conversación y perdía actividad de
  # conversaciones viejas. Ahora cuenta por la fecha de los mensajes.
  it 'incluye actividad del rango en conversaciones creadas ANTES del rango', :aggregate_failures do
    # Conversación vieja (creada hace 40 días), mensaje dentro del rango de hoy.
    conversation.update_column(:created_at, 40.days.ago) # rubocop:disable Rails/SkipsModelValidations
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: agent, created_at: 1.hour.ago)

    params = { from: 2.hours.ago.to_i.to_s, to: 5.minutes.from_now.to_i.to_s }
    s = builder(params).summary
    expect(s[:sent]).to eq(1) # antes daba 0 porque la conversación quedaba fuera
  end

  it 'excluye mensajes fuera del rango aunque la conversación sea reciente', :aggregate_failures do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: agent, created_at: 10.days.ago)

    params = { from: 2.hours.ago.to_i.to_s, to: 5.minutes.from_now.to_i.to_s }
    s = builder(params).summary
    expect(s[:sent]).to eq(0) # el mensaje de hace 10 días no cuenta en el rango de hoy
  end

  it 'muestra una etiqueta aplicada antes del rango pero aún activa en él', :aggregate_failures do
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: agent, created_at: 1.hour.ago)
    conversation.update!(label_list: ['detener-bot-masivo'])
    log = JabvoxConversationLabelLog.find_by(conversation_id: conversation.id, label_jabvox: 'detener-bot-masivo')
    log.update!(applied_at_jabvox: 3.days.ago) # aplicada antes del rango, aún activa

    params = { from: 2.hours.ago.to_i.to_s, to: 5.minutes.from_now.to_i.to_s }
    durations = builder(params).label_durations
    expect(durations.map { |r| r[:label] }).to include('detener-bot-masivo')
  end

  it 'logs label apply/remove intervals and aggregates duration', :aggregate_failures do
    conversation.update!(label_list: ['ventas'])
    log = JabvoxConversationLabelLog.find_by(conversation_id: conversation.id, label_jabvox: 'ventas')
    expect(log).to be_present
    expect(log.removed_at_jabvox).to be_nil

    log.update!(applied_at_jabvox: 30.minutes.ago)
    conversation.update!(label_list: [])
    expect(log.reload.removed_at_jabvox).to be_present

    durations = builder.label_durations
    row = durations.find { |r| r[:label] == 'ventas' }
    expect(row).to be_present
    expect(row[:total_seconds]).to be >= 1700 # ~30 min
    expect(row[:occurrences]).to eq(1)
  end

  it 'lists label detail per lead with contact and duration', :aggregate_failures do
    conversation.update!(label_list: ['ventas'])
    log = JabvoxConversationLabelLog.find_by(conversation_id: conversation.id, label_jabvox: 'ventas')
    log.update!(applied_at_jabvox: 2.hours.ago)

    leads = builder.label_lead_details('ventas')
    expect(leads.size).to eq(1)
    lead = leads.first
    expect(lead[:conversation_id]).to eq(conversation.id)
    expect(lead[:contact_name]).to eq(contact.name)
    expect(lead[:active]).to be(true)
    expect(lead[:duration_seconds]).to be >= 7000 # ~2h
  end

  it 'filters label detail by the given label', :aggregate_failures do
    conversation.update!(label_list: %w[ventas soporte])
    leads = builder.label_lead_details('soporte')
    expect(leads.map { |l| l[:label] }.uniq).to eq(['soporte'])
  end

  it 'breaks messages down by media type', :aggregate_failures do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'hola')
    img = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    img.attachments.create!(account: account, file_type: :image)

    bd = builder.summary[:incoming_by_type]
    expect(bd[:total]).to eq(2)
    expect(bd[:image]).to eq(1)
    expect(bd[:text]).to eq(1)
  end

  it 'computes time_to_deliver and time_to_read in the summary', :aggregate_failures do
    msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent, created_at: 1.hour.ago)
    MessageStatusEvent.create!(account: account, message: msg, status: :delivered, occurred_at: 1.hour.ago + 20)
    MessageStatusEvent.create!(account: account, message: msg, status: :read, occurred_at: 1.hour.ago + 300)

    s = builder.summary
    expect(s[:time_to_deliver][:count]).to eq(1)
    expect(s[:time_to_read][:count]).to eq(1)
    expect(s[:time_to_read][:median]).to be >= 250
  end
end
