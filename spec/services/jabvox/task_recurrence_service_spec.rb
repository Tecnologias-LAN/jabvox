# frozen_string_literal: true

require 'rails_helper'

# Una tarea recurrente engendra la siguiente al completarse, no por calendario.
RSpec.describe Jabvox::TaskRecurrenceService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: user.id) }

  let!(:initial_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Por hacer',
                         position_jabvox: 0, role_jabvox: 'initial')
  end
  let!(:other_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 1)
  end

  def task(**attrs)
    account.jabvox_tasks.create!(
      { board_id: board.id, stage_id: other_stage.id, title_jabvox: 'Informe',
        due_at_jabvox: Time.zone.parse('2026-09-28 09:00'), created_by_id: user.id }.merge(attrs)
    )
  end

  describe 'al completar una tarea recurrente' do
    it 'crea la siguiente con la fecha desplazada' do
      original = task(recurrence_unit_jabvox: 'week', recurrence_count_jabvox: 1)

      original.update!(status_jabvox: 'done')

      siguiente = account.jabvox_tasks.find_by(recurrence_parent_id: original.id)
      expect(siguiente.due_at_jabvox).to eq(Time.zone.parse('2026-10-05 09:00'))
    end

    it 'la crea abierta y en la etapa marcada como inicial' do
      original = task(recurrence_unit_jabvox: 'month', recurrence_count_jabvox: 1)

      original.update!(status_jabvox: 'done')

      siguiente = account.jabvox_tasks.find_by(recurrence_parent_id: original.id)
      expect(siguiente.status_jabvox).to eq('open')
      expect(siguiente.stage_id).to eq(initial_stage.id)
    end

    it 'cuenta desde el vencimiento, no desde hoy: cerrar tarde no corre la serie' do
      original = task(due_at_jabvox: 10.days.ago, recurrence_unit_jabvox: 'week',
                      recurrence_count_jabvox: 1)

      original.update!(status_jabvox: 'done')

      siguiente = account.jabvox_tasks.find_by(recurrence_parent_id: original.id)
      expect(siguiente.due_at_jabvox).to be_within(1.minute).of(3.days.ago)
    end

    it 'encadena la serie al primer ancestro, no al eslabón anterior' do
      primera = task(recurrence_unit_jabvox: 'week', recurrence_count_jabvox: 1)
      primera.update!(status_jabvox: 'done')
      segunda = account.jabvox_tasks.find_by(recurrence_parent_id: primera.id)

      segunda.update!(status_jabvox: 'done')

      tercera = account.jabvox_tasks.where(recurrence_parent_id: primera.id).order(:id).last
      expect(tercera.recurrence_parent_id).to eq(primera.id)
    end

    it 'deja de repetirse pasada la fecha tope' do
      original = task(recurrence_unit_jabvox: 'week', recurrence_count_jabvox: 1,
                      recurrence_until_jabvox: Time.zone.parse('2026-09-30 00:00'))

      original.update!(status_jabvox: 'done')

      expect(account.jabvox_tasks.where(recurrence_parent_id: original.id)).to be_empty
    end
  end

  describe 'la columna sigue al estado' do
    let!(:done_stage) do
      board.stages.create!(account_id: account.id, name_jabvox: 'Hecho',
                           position_jabvox: 5, role_jabvox: 'done')
    end

    it 'completar la mueve a la columna de completadas' do
      pendiente = task

      pendiente.update!(status_jabvox: 'done')

      expect(pendiente.reload.stage_id).to eq(done_stage.id)
    end

    it 'reabrir la devuelve a la columna inicial' do
      pendiente = task
      pendiente.update!(status_jabvox: 'done')

      pendiente.update!(status_jabvox: 'open')

      expect(pendiente.reload.stage_id).to eq(initial_stage.id)
    end

    it 'deja constancia del movimiento en el historial' do
      pendiente = task

      pendiente.update!(status_jabvox: 'done')

      movimiento = pendiente.activities.where(action_jabvox: 'stage_changed').last
      expect(movimiento.metadata_jabvox['reason']).to eq('status_done')
    end

    # Un tablero sin columna marcada no se toca: moverla a una cualquiera sería peor.
    it 'no mueve nada si el tablero no marcó columna de completadas' do
      done_stage.update!(role_jabvox: nil)
      pendiente = task

      pendiente.update!(status_jabvox: 'done')

      expect(pendiente.reload.stage_id).to eq(other_stage.id)
    end
  end

  it 'una tarea normal no genera copias' do
    normal = task

    normal.update!(status_jabvox: 'done')

    expect(account.jabvox_tasks.where(recurrence_parent_id: normal.id)).to be_empty
  end

  it 'reabrir y volver a cerrar no duplica la serie sin avanzar' do
    original = task(recurrence_unit_jabvox: 'week', recurrence_count_jabvox: 1)
    original.update!(status_jabvox: 'done')
    original.update!(status_jabvox: 'open')

    original.update!(status_jabvox: 'done')

    fechas = account.jabvox_tasks.where(recurrence_parent_id: original.id).pluck(:due_at_jabvox)
    expect(fechas.uniq.size).to eq(1)
  end
end
