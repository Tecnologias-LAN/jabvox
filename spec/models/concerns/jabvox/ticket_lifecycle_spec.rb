require 'rails_helper'

RSpec.describe Jabvox::TicketLifecycle do
  let(:account) { create(:account) }
  let(:ticket) { create(:jabvox_ticket, account: account) }

  describe 'máquina de estados' do
    it 'permite transiciones válidas' do
      ticket.change_status!('in_progress')
      expect(ticket.reload.status_jabvox).to eq('in_progress')
      ticket.change_status!('resolved')
      expect(ticket.reload.status_jabvox).to eq('resolved')
    end

    it 'rechaza una transición inválida (closed → in_progress)' do
      ticket.change_status!('closed')
      expect { ticket.change_status!('in_progress') }
        .to raise_error(Jabvox::TicketLifecycle::InvalidTransitionError)
    end

    it 'no rechaza pasar al mismo estado (idempotente)' do
      expect { ticket.change_status!(ticket.status_jabvox) }.not_to raise_error
    end

    it 'reabrir un cerrado sí es válido' do
      ticket.change_status!('closed')
      expect { ticket.reopen! }.not_to raise_error
      expect(ticket.reload.status_jabvox).to eq('reopened')
    end
  end

  describe 'soft delete' do
    it 'archive! marca deleted_at y registra actividad, sin borrar la fila' do
      expect { ticket.archive! }
        .to change { ticket.reload.archived? }.from(false).to(true)
      expect(JabvoxTicket.where(id: ticket.id)).to exist
      expect(ticket.activities.where(action_jabvox: 'archived')).to exist
    end

    it 'el scope kept excluye archivados' do
      ticket.archive!
      expect(JabvoxTicket.kept).not_to include(ticket)
      expect(JabvoxTicket.archived).to include(ticket)
    end
  end

  describe 'bloqueo optimista' do
    it 'lanza StaleObjectError ante escritura concurrente' do
      a = JabvoxTicket.find(ticket.id)
      b = JabvoxTicket.find(ticket.id)
      a.update!(title_jabvox: 'A gana')
      expect { b.update!(title_jabvox: 'B pierde') }
        .to raise_error(ActiveRecord::StaleObjectError)
    end
  end
end
