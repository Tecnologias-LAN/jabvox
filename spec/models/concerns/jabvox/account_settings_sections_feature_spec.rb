require 'rails_helper'

# Siete secciones de Configuración estaban siempre visibles, sin forma de apagarlas por
# cuenta. Tres de ellas (sla, audit_logs, canned_responses) son features de Chatwoot, así
# que el interruptor de cuenta se suma al global en vez de sustituirlo.
describe Jabvox::AccountSettingsSectionsFeature do
  let(:account) { create(:account) }

  describe 'secciones propias de Jabvox' do
    it 'están encendidas por defecto, para no quitar nada al desplegar' do
      %w[jabvox_ip_whitelist jabvox_management_states jabvox_field_security
         jabvox_conversation_workflow].each do |feature|
        expect(account.feature_enabled?(feature)).to be(true), "#{feature} llegó apagada"
      end
    end

    it 'se apagan por cuenta' do
      account.update!(jabvox_ip_whitelist_enabled_jabvox: false)
      expect(account.reload.feature_enabled?('jabvox_ip_whitelist')).to be false
      # Apagar una no toca las demás.
      expect(account.feature_enabled?('jabvox_field_security')).to be true
    end

    it 'aparecen en enabled_features, que es lo que lee el frontend' do
      account.update!(jabvox_field_security_enabled_jabvox: false)
      expect(account.reload.enabled_features).to include(
        'jabvox_field_security' => false, 'jabvox_ip_whitelist' => true
      )
    end
  end

  describe 'features de Chatwoot' do
    before { account.enable_features('canned_responses') }

    it 'el interruptor de la cuenta puede apagar lo que el plan concede' do
      expect(account.feature_enabled?('canned_responses')).to be true

      account.update!(jabvox_canned_responses_enabled_jabvox: false)

      expect(account.reload.feature_enabled?('canned_responses')).to be false
    end

    # Si el interruptor pudiera encender por su cuenta, una cuenta sin el plan tendría
    # acceso a una función que no le corresponde.
    it 'el interruptor NO enciende lo que el plan no concede' do
      account.disable_features('sla')
      account.update!(jabvox_sla_enabled_jabvox: true)

      expect(account.reload.feature_enabled?('sla')).to be false
    end
  end

  it 'no afecta a otras cuentas' do
    otra = create(:account)
    account.update!(jabvox_management_states_enabled_jabvox: false)

    expect(otra.feature_enabled?('jabvox_management_states')).to be true
  end

  it 'deja pasar las features que no gestiona' do
    expect { account.feature_enabled?('inbox_management') }.not_to raise_error
  end
end
