# frozen_string_literal: true

require 'rails_helper'

# Regresión de los bugs de reintentos de la auditoría del dialer:
#   D-01: attempts_jabvox se reseteaba a 0 en cada marcación => max_retries nunca aplicaba.
#   D-02: Float::INFINITY bindeado a columna integer abortaba la reserva con max_retries=0.
#   D-16: se respeta retry_interval antes de re-marcar.
RSpec.describe Jabvox::DialerContactPickerService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+573001112233') }

  # Lead mínimo (jabvox_leads exige contact_id y lead_number).
  let!(:lead) do
    JabvoxLead.create!(account_id: account.id, contact_id: contact.id, lead_number: 1)
  end

  let(:campaign) do
    JabvoxDialerCampaign.create!(
      account_id: account.id, name_jabvox: 'Test', status_jabvox: 'active',
      dial_mode_jabvox: 'one_by_one', retry_statuses_jabvox: %w[no_answer],
      max_retries_jabvox: max_retries, retry_interval_jabvox: 1
    )
  end
  let(:max_retries) { 2 }

  # Reserva una llamada como lo hace el controlador (SIN fijar attempts_jabvox).
  def reserve!
    described_class.new(account, campaign).pick_and_reserve do |picked|
      { name_jabvox: picked.contact.name.to_s, phone_jabvox: '3001112233', status_jabvox: 'calling' }
    end
  end

  describe 'contador de intentos (D-01)' do
    it 'incrementa attempts_jabvox en cada marcación en vez de resetearlo a 0' do
      _lead1, cc1 = reserve!
      expect(cc1.attempts_jabvox).to eq(1)

      # El lead vuelve a la cola tras no contestar.
      cc1.update!(status_jabvox: 'no_answer', last_attempt_at_jabvox: 2.minutes.ago)
      _lead2, cc2 = reserve!

      expect(cc2.id).to eq(cc1.id) # reusa la misma fila
      expect(cc2.attempts_jabvox).to eq(2) # NO vuelve a 1
    end

    it 'deja de re-marcar cuando attempts supera max_retries' do
      _l, cc = reserve!
      # attempts ya por encima del tope (max_retries=2): el filtro attempts<=max
      # ya no lo selecciona, así que no vuelve a marcar.
      cc.update!(status_jabvox: 'no_answer', attempts_jabvox: 3, last_attempt_at_jabvox: 2.minutes.ago)

      lead_again, = reserve!
      expect(lead_again).to be_nil
    end
  end

  describe 'max_retries = 0 (sin tope) (D-02)' do
    let(:max_retries) { 0 }

    it 'no lanza excepción SQL y sigue re-marcando sin importar el número de intentos' do
      _l, cc = reserve!
      # attempts muy alto: con Float::INFINITY esto reventaba (PG 22P02). Con el
      # fix, max=0 omite la cláusula y el lead sigue siendo elegible.
      cc.update!(status_jabvox: 'no_answer', attempts_jabvox: 99, last_attempt_at_jabvox: 2.minutes.ago)

      result = nil
      expect { result = reserve! }.not_to raise_error
      expect(result.last.attempts_jabvox).to eq(100)
    end
  end

  describe 'intervalo de reintento (D-16)' do
    it 'no re-marca antes de que pase retry_interval_jabvox' do
      _l, cc = reserve!
      # Último intento hace 10 segundos; intervalo configurado = 1 minuto.
      cc.update!(status_jabvox: 'no_answer', last_attempt_at_jabvox: 10.seconds.ago)

      lead_again, = reserve!
      expect(lead_again).to be_nil
    end
  end
end
