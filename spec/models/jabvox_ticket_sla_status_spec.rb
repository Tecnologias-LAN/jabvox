require 'rails_helper'

RSpec.describe JabvoxTicket do
  let(:account) { create(:account) }

  describe '#sla_status (semáforo)' do
    it 'es none sin due_at' do
      ticket = build(:jabvox_ticket, account: account, due_at_jabvox: nil)
      expect(ticket.sla_status).to eq('none')
    end

    it 'es red cuando ya venció y sigue abierto' do
      ticket = create(:jabvox_ticket, account: account)
      ticket.update!(due_at_jabvox: 1.hour.ago)
      expect(ticket.sla_status).to eq('red')
    end

    it 'es amber cuando queda poco margen' do
      ticket = create(:jabvox_ticket, account: account)
      ticket.update!(due_at_jabvox: 10.minutes.from_now)
      expect(ticket.sla_status).to eq('amber')
    end

    it 'es green con margen holgado' do
      ticket = create(:jabvox_ticket, account: account)
      ticket.update!(due_at_jabvox: 5.days.from_now)
      expect(ticket.sla_status).to eq('green')
    end

    it 'es none si el ticket ya está resuelto' do
      ticket = create(:jabvox_ticket, account: account)
      ticket.update!(due_at_jabvox: 1.hour.ago)
      ticket.change_status!('in_progress')
      ticket.resolve!(resolution: 'listo', resolution_type: :solved)
      expect(ticket.sla_status).to eq('none')
    end
  end

  describe 'validación de adjuntos (solo imágenes)' do
    let(:ticket) { build(:jabvox_ticket, account: account) }

    it 'rechaza un archivo que no es imagen (p. ej. PDF)' do
      ticket.attachments.attach(
        io: StringIO.new('%PDF-1.4'), filename: 'doc.pdf', content_type: 'application/pdf'
      )
      expect(ticket).not_to be_valid
      expect(ticket.errors[:attachments].join).to match(/solo se permiten imágenes/)
    end

    it 'rechaza un ejecutable' do
      ticket.attachments.attach(
        io: StringIO.new('MZ'), filename: 'malware.exe', content_type: 'application/x-msdownload'
      )
      expect(ticket).not_to be_valid
    end

    it 'acepta una imagen PNG' do
      ticket.attachments.attach(
        io: StringIO.new('\x89PNG'), filename: 'captura.png', content_type: 'image/png'
      )
      expect(ticket).to be_valid
    end
  end
end
