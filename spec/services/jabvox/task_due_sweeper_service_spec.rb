# frozen_string_literal: true

require 'rails_helper'

# Pasada diaria: avisa de lo que vence y aparta lo vencido sin completar.
RSpec.describe Jabvox::TaskDueSweeperService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: user.id) }

  let!(:working_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 0)
  end
  let!(:inactive_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Inactiva',
                         position_jabvox: 9, role_jabvox: 'inactive')
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def task(**attrs)
    account.jabvox_tasks.create!(
      { board_id: board.id, stage_id: working_stage.id, title_jabvox: 'Pendiente',
        created_by_id: user.id }.merge(attrs)
    )
  end

  describe 'tareas vencidas' do
    it 'manda a la etapa inactiva lo vencido sin completar' do
      vencida = task(due_at_jabvox: 2.days.ago)

      described_class.new.call

      expect(vencida.reload.stage_id).to eq(inactive_stage.id)
    end

    it 'deja el motivo en el historial, para saber por qué se movió' do
      vencida = task(due_at_jabvox: 2.days.ago)

      described_class.new.call

      movimiento = vencida.activities.where(action_jabvox: 'stage_changed').last
      expect(movimiento.metadata_jabvox['reason']).to eq('vencida')
    end

    it 'no toca una tarea ya completada' do
      completada = task(due_at_jabvox: 2.days.ago, status_jabvox: 'done')

      described_class.new.call

      expect(completada.reload.stage_id).to eq(working_stage.id)
    end

    it 'no toca una tarea que aún no vence' do
      futura = task(due_at_jabvox: 3.days.from_now)

      described_class.new.call

      expect(futura.reload.stage_id).to eq(working_stage.id)
    end

    # Un tablero sin etapa inactiva marcada se salta: mover a una columna cualquiera
    # sería peor que no mover.
    it 'no mueve nada si el tablero no marcó una etapa inactiva' do
      inactive_stage.update!(role_jabvox: nil)
      vencida = task(due_at_jabvox: 2.days.ago)

      described_class.new.call

      expect(vencida.reload.stage_id).to eq(working_stage.id)
    end
  end

  describe 'recordatorios' do
    it 'avisa una sola vez de lo que vence pronto' do
      proxima = task(due_at_jabvox: 6.hours.from_now)
      proxima.sync_assignees!([user.id])

      described_class.new.call
      primera_marca = proxima.reload.reminder_sent_at_jabvox
      described_class.new.call

      expect(primera_marca).to be_present
      expect(proxima.reload.reminder_sent_at_jabvox).to eq(primera_marca)
    end
  end
end
