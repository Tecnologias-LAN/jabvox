# frozen_string_literal: true

require 'rails_helper'

# Correo libre: destinatario, asunto y cuerpo escritos a mano (sin plantilla).
# Lo usan los flujos de Automations para enviar el informe final del bucle.
RSpec.describe 'Jabvox free-form email', type: :request do
  let(:account) { create(:account, jabvox_email_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  let!(:smtp_config) do
    JabvoxSmtpConfig.create!(
      account: account, address: 'smtp.example.com', port: 587,
      from_email: 'no-reply@example.com', from_name: 'Jabvox',
      authentication: 'login'
    )
  end

  def url = "/api/v1/accounts/#{account.id}/jabvox/email/send_message"

  def send_email(params)
    post url, params: params, headers: admin.create_new_auth_token, as: :json
    response.parsed_body
  end

  # El envío real se corta en el servicio: aquí se comprueba el contrato HTTP.
  def stub_sender
    sender = instance_double(Jabvox::EmailSenderService, deliver!: true)
    allow(Jabvox::EmailSenderService).to receive(:new).and_return(sender)
    sender
  end

  it 'envía a la dirección libre con el asunto y el cuerpo dados' do
    stub_sender

    body = send_email(to: 'destino@ejemplo.com', subject: 'Informe', body: 'Todo bien')

    expect(response).to have_http_status(:success)
    expect(body['success']).to be(true)
    expect(Jabvox::EmailSenderService).to have_received(:new).with(
      hash_including(to: 'destino@ejemplo.com', subject: 'Informe')
    )
  end

  it 'convierte los saltos de línea del informe en <br> (texto plano por defecto)' do
    stub_sender

    send_email(to: 'destino@ejemplo.com', subject: 'Informe', body: "Linea 1\nLinea 2")

    expect(Jabvox::EmailSenderService).to have_received(:new).with(
      hash_including(html_body: "Linea 1<br>\nLinea 2")
    )
  end

  it 'escapa el HTML del cuerpo cuando no se pide is_html' do
    stub_sender

    send_email(to: 'destino@ejemplo.com', subject: 'X', body: '<script>alert(1)</script>')

    expect(Jabvox::EmailSenderService).to have_received(:new).with(
      hash_including(html_body: '&lt;script&gt;alert(1)&lt;/script&gt;')
    )
  end

  it 'respeta el HTML tal cual con is_html' do
    stub_sender

    send_email(to: 'destino@ejemplo.com', subject: 'X', body: '<b>hola</b>', is_html: true)

    expect(Jabvox::EmailSenderService).to have_received(:new).with(
      hash_including(html_body: '<b>hola</b>')
    )
  end

  it 'rechaza un destinatario con formato inválido' do
    body = send_email(to: 'no-es-un-email', subject: 'X', body: 'Y')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['error']).to eq('Recipient email is not valid')
  end

  # Inyección de cabeceras: un salto de línea permitiría colar Bcc:/Cc:.
  it 'rechaza un destinatario que intente inyectar cabeceras' do
    send_email(to: "ok@ejemplo.com\nBcc: victima@ejemplo.com", subject: 'X', body: 'Y')

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rechaza varios destinatarios en un solo campo' do
    send_email(to: 'uno@ejemplo.com, dos@ejemplo.com', subject: 'X', body: 'Y')

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'exige asunto y cuerpo' do
    send_email(to: 'destino@ejemplo.com', subject: '', body: 'Y')
    expect(response).to have_http_status(:unprocessable_entity)

    send_email(to: 'destino@ejemplo.com', subject: 'X', body: '')
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'devuelve 422 si no hay SMTP configurado' do
    smtp_config.destroy!

    body = send_email(to: 'destino@ejemplo.com', subject: 'X', body: 'Y')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(body['error']).to eq('SMTP not configured')
  end

  it 'devuelve 403 si el módulo de correo está apagado' do
    account.update!(jabvox_email_enabled_jabvox: false)

    send_email(to: 'destino@ejemplo.com', subject: 'X', body: 'Y')

    expect(response).to have_http_status(:forbidden)
  end

  it 'deniega a un rol personalizado sin jabvox_email_manage' do
    role = CustomRole.create!(account: account, name: 'Solo lectura', permissions: [])
    account.account_users.find_by(user: admin).update!(custom_role: role, role: :agent)

    send_email(to: 'destino@ejemplo.com', subject: 'X', body: 'Y')

    expect(response).to have_http_status(:forbidden)
  end
end
