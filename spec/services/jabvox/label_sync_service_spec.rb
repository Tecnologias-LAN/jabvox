# frozen_string_literal: true

require 'rails_helper'

# Contacto y conversaciones abiertas comparten etiquetas en ambos sentidos.
RSpec.describe Jabvox::LabelSyncService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  def conversation(status: :open, inbox_for: nil)
    create(:conversation, account: account, contact: contact,
                          inbox: inbox_for || inbox, status: status)
  end

  it 'lleva las etiquetas del contacto a sus conversaciones abiertas' do
    abierta = conversation

    contact.update_labels(%w[vip urgente])

    expect(abierta.reload.label_list).to match_array(%w[vip urgente])
  end

  it 'lleva las etiquetas de una conversación al contacto' do
    abierta = conversation

    abierta.update_labels(%w[soporte])

    expect(contact.reload.label_list).to match_array(%w[soporte])
  end

  it 'propaga entre conversaciones abiertas del mismo contacto' do
    una = conversation
    otra = conversation

    una.update_labels(%w[vip])

    expect(otra.reload.label_list).to match_array(%w[vip])
  end

  # Una conversación resuelta es historial: con qué se cerró el caso no se reescribe.
  it 'no toca las conversaciones resueltas' do
    resuelta = conversation(status: :resolved)

    contact.update_labels(%w[vip])

    expect(resuelta.reload.label_list).to be_empty
  end

  it 'alcanza conversaciones de bandejas distintas' do
    otra_bandeja = conversation(inbox_for: create(:inbox, account: account))

    contact.update_labels(%w[vip])

    expect(otra_bandeja.reload.label_list).to match_array(%w[vip])
  end

  it 'no entra en bucle entre contacto y conversación' do
    abierta = conversation

    expect { abierta.update_labels(%w[vip]) }.not_to raise_error
    expect(contact.reload.label_list).to match_array(%w[vip])
    expect(abierta.reload.label_list).to match_array(%w[vip])
  end

  it 'quitar una etiqueta también se propaga' do
    abierta = conversation
    contact.update_labels(%w[vip urgente])

    contact.update_labels(%w[vip])

    expect(abierta.reload.label_list).to match_array(%w[vip])
  end
end
