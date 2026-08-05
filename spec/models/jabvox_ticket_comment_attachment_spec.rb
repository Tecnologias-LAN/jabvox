# frozen_string_literal: true

require 'rails_helper'

# Adjuntos de comentarios de tickets: solo imágenes, mismo servicio de ActiveStorage
# que los tickets y las bandejas.
RSpec.describe JabvoxTicketComment do
  let(:account) { create(:account) }
  let(:ticket) { create(:jabvox_ticket, account: account) }
  let(:user) { create(:user) }

  def build_comment
    described_class.new(ticket: ticket, user: user, body_jabvox: 'seguimiento')
  end

  it 'acepta una imagen adjunta' do
    comment = build_comment
    comment.attachments.attach(
      io: StringIO.new('\x89PNG'), filename: 'evidencia.png', content_type: 'image/png'
    )
    expect(comment).to be_valid
  end

  it 'rechaza un adjunto que no es imagen' do
    comment = build_comment
    comment.attachments.attach(
      io: StringIO.new('%PDF'), filename: 'doc.pdf', content_type: 'application/pdf'
    )
    expect(comment).not_to be_valid
    expect(comment.errors[:attachments].join).to match(/solo se permiten imágenes/)
  end

  it 'guarda las imágenes en el servicio de ActiveStorage por defecto (junto a las bandejas)' do
    comment = build_comment
    comment.attachments.attach(
      io: StringIO.new('\x89PNG'), filename: 'foto.png', content_type: 'image/png'
    )
    comment.save!
    expect(comment.attachments.first.blob.service_name).to eq(ActiveStorage::Blob.service.name.to_s)
  end
end
