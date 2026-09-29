# frozen_string_literal: true

require 'rails_helper'

# Columna y estado cuentan lo mismo: completar lleva la tarjeta a la columna de
# terminadas, y arrastrarla allí la marca como completada.
RSpec.describe JabvoxTask, type: :model do
  let(:account) { create(:account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Operaciones') }

  let!(:initial) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Inicio',
                         role_jabvox: 'initial', position_jabvox: 1)
  end
  let!(:middle) do
    board.stages.create!(account_id: account.id, name_jabvox: 'En curso', position_jabvox: 2)
  end
  let!(:done) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Terminado',
                         role_jabvox: 'done', position_jabvox: 3)
  end

  let(:task) do
    account.jabvox_tasks.create!(board_id: board.id, stage_id: middle.id,
                                 title_jabvox: 'Llamar', status_jabvox: 'open')
  end

  describe 'al cambiar el estado' do
    it 'completar la lleva a la columna de terminadas' do
      task.update!(status_jabvox: 'done')
      expect(task.reload.stage_id).to eq(done.id)
    end

    it 'reabrir la devuelve a la columna inicial' do
      task.update!(status_jabvox: 'done')
      task.update!(status_jabvox: 'open')
      expect(task.reload.stage_id).to eq(initial.id)
    end
  end

  describe 'al arrastrar la tarjeta' do
    it 'moverla a la columna de terminadas la marca completada' do
      task.update!(stage_id: done.id)
      expect(task.reload.status_jabvox).to eq('done')
    end

    it 'sacarla de terminadas la reabre' do
      task.update!(stage_id: done.id)
      task.update!(stage_id: middle.id)
      expect(task.reload.status_jabvox).to eq('open')
    end

    it 'moverla entre columnas intermedias no toca el estado' do
      expect { task.update!(stage_id: initial.id) }
        .not_to(change { task.reload.status_jabvox })
    end
  end

  describe 'columna inicial del tablero' do
    it 'prefiere la marcada aunque no sea la primera por posición' do
      initial.update!(position_jabvox: 99)
      expect(board.reload.initial_stage).to eq(initial)
    end

    it 'sin ninguna marcada usa la primera por posición' do
      initial.update!(role_jabvox: nil, position_jabvox: 8)
      expect(board.reload.initial_stage).to eq(middle)
    end

    it 'sin columna de terminadas, completar no mueve la tarjeta' do
      done.update!(role_jabvox: nil)
      expect { task.update!(status_jabvox: 'done') }
        .not_to(change { task.reload.stage_id })
    end
  end
end
