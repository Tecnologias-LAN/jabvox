# frozen_string_literal: true

require 'rails_helper'

# Endpoint que expone desde cuándo está aplicada una etiqueta a una conversación,
# usando jabvox_conversation_label_logs. Solo informa (applied_at + horas); NO decide
# umbrales de tiempo — de eso se encarga quien consume (n8n).
RSpec.describe 'Jabvox label logs', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:other_conversation) { create(:conversation, account: account) }

  def url = "/api/v1/accounts/#{account.id}/jabvox/label_logs"

  def get_logs(params)
    get url, params: params, headers: admin.create_new_auth_token, as: :json
    response.parsed_body
  end

  # Crea un intervalo abierto (etiqueta aún puesta) aplicado hace `hours` horas.
  def open_log(conv, label, hours)
    JabvoxConversationLabelLog.create!(
      account_id: account.id, conversation_id: conv.id,
      label_jabvox: label, applied_at_jabvox: hours.hours.ago
    )
  end

  it 'exige el parámetro label' do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'devuelve todas las conversaciones con la etiqueta puesta y su tiempo aplicado' do
    vieja = open_log(conversation, 'detener-bot-masivo', 30)
    open_log(other_conversation, 'detener-bot-masivo', 2)

    body = get_logs(label: 'detener-bot-masivo')
    ids = body['data'].map { |r| r['conversation_id'] }

    expect(ids).to contain_exactly(conversation.id, other_conversation.id)
    row = body['data'].find { |r| r['conversation_id'] == conversation.id }
    expect(row['hours_applied']).to be >= 30
    expect(row['applied_at']).to eq(vieja.applied_at_jabvox.iso8601)
    expect(row['applied_at_epoch']).to eq(vieja.applied_at_jabvox.to_i)
  end

  it 'no incluye etiquetas ya retiradas (intervalo cerrado)' do
    log = open_log(conversation, 'detener-bot-masivo', 30)
    log.update!(removed_at_jabvox: Time.current)

    body = get_logs(label: 'detener-bot-masivo')
    expect(body['count']).to eq(0)
  end

  it 'no mezcla otras etiquetas' do
    open_log(conversation, 'otra-etiqueta', 30)
    body = get_logs(label: 'detener-bot-masivo')
    expect(body['count']).to eq(0)
  end
end
