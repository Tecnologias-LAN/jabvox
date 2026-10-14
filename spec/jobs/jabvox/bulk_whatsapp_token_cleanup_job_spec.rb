require 'rails_helper'

# El cleanup es el respaldo por si el callback final de n8n nunca llega. Borraba el token
# a ciegas por tiempo: en un envío más lento de lo calculado, mataba la credencial con
# mensajes aún en vuelo y el resto fallaba con "401 Invalid Access Token".
describe Jabvox::BulkWhatsappTokenCleanupJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:token) { AccessToken.create!(owner: user, expires_at: nil) }
  let(:batch) do
    JabvoxBulkWhatsappBatch.create!(account: account, sender_user: user, status_jabvox: 'running',
                                    access_token_id_jabvox: token.id, payload_jabvox: {})
  end

  def add_recipient(status)
    JabvoxBulkWhatsappRecipient.create!(batch: batch, account: account,
                                        phone_number_jabvox: '573000000000', status_jabvox: status)
  end

  it 'no borra el token mientras queden destinatarios pendientes' do
    add_recipient('sent')
    add_recipient('pending')

    described_class.perform_now(token.id)

    expect(AccessToken.exists?(token.id)).to be(true), 'borró el token con envíos en vuelo'
  end

  it 'se reprograma para volver a comprobarlo' do
    add_recipient('pending')

    expect { described_class.perform_now(token.id) }
      .to have_enqueued_job(described_class).with(token.id, 1)
  end

  it 'borra el token cuando ya no queda nada pendiente' do
    add_recipient('sent')
    add_recipient('failed')

    described_class.perform_now(token.id)

    expect(AccessToken.exists?(token.id)).to be(false)
    expect(batch.reload.access_token_id_jabvox).to be_nil
  end

  # Si algo deja el batch colgado, el token no puede quedar vivo indefinidamente.
  it 'borra el token al agotar los reintentos, aunque siga pendiente' do
    add_recipient('pending')

    described_class.perform_now(token.id, described_class::MAX_REINTENTOS)

    expect(AccessToken.exists?(token.id)).to be(false)
  end

  it 'borra el token suelto que ya no pertenece a ningún envío' do
    huerfano = AccessToken.create!(owner: user, expires_at: nil)

    described_class.perform_now(huerfano.id)

    expect(AccessToken.exists?(huerfano.id)).to be(false)
  end
end
