# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxBulkWhatsappBatch do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # El token del envío se revoca cuando el batch llega a estado terminal (lo confirma n8n).
  describe '#recalculate_status! token revocation' do
    let(:token) { AccessToken.create!(owner: user, expires_at: nil) }
    let(:batch) do
      described_class.create!(account: account, sender_user: user, status_jabvox: 'running',
                              access_token_id_jabvox: token.id, payload_jabvox: {})
    end

    it 'revoca el token al completar (todos enviados)' do
      add_recipient(batch, 'sent')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('completed')
      expect(AccessToken.exists?(token.id)).to be(false)
      expect(batch.access_token_id_jabvox).to be_nil
    end

    it 'NO revoca el token mientras siga en running (aún procesando)' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'pending')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('running')
      expect(AccessToken.exists?(token.id)).to be(true)
    end

    it 'revoca el token en estado partial (hubo fallidos)' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'failed')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('partial')
      expect(AccessToken.exists?(token.id)).to be(false)
    end

    # El caso que costó 341 mensajes en el envío 191: Meta rechaza a muchos, esos entran
    # como `failed` al instante, y la suma sent+failed alcanzaba el total ANTES de que n8n
    # enviara los últimos. El batch se cerraba, revocaba el token y el resto moría con
    # "401 Invalid Access Token".
    it 'NO cierra mientras queden pendientes, aunque sent+failed ya sume el total' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'failed')
      add_recipient(batch, 'pending')

      # n8n reporta su último chunk, pero todavía hay un destinatario sin resultado.
      batch.recalculate_status!(final: true)

      expect(batch.reload.status_jabvox).to eq('running')
      expect(AccessToken.exists?(token.id)).to be(true), 'el token se revocó con envíos en vuelo'
    end

    it 'cierra en cuanto el último pendiente reporta' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'failed')
      pendiente = add_recipient(batch, 'pending')

      batch.recalculate_status!(final: true)
      expect(batch.reload.status_jabvox).to eq('running')

      pendiente.update!(status_jabvox: 'sent')
      batch.recalculate_status!(final: true)

      expect(batch.reload.status_jabvox).to eq('partial')
      expect(AccessToken.exists?(token.id)).to be(false)
    end

    # Respaldo: si un chunk de n8n se pierde y nunca llega `final`, el batch no puede
    # quedarse colgado en running con el token vivo para siempre.
    it 'cierra sin `final` cuando ya todos reportaron' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'failed')

      batch.recalculate_status!

      expect(batch.reload.status_jabvox).to eq('partial')
    end

    # Última línea de defensa: aunque se invoque la revocación directamente, el token no
    # puede desaparecer mientras n8n siga enviando.
    it 'revoke_access_token! no destruye el token si quedan pendientes' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'pending')

      batch.revoke_access_token!

      expect(AccessToken.exists?(token.id)).to be(true)
      expect(batch.reload.access_token_id_jabvox).to eq(token.id)
    end

    def add_recipient(batch, status)
      JabvoxBulkWhatsappRecipient.create!(
        batch: batch, account: account, phone_number_jabvox: '573000000000',
        status_jabvox: status
      )
    end
  end
end
