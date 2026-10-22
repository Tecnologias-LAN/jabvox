# frozen_string_literal: true

require 'rails_helper'

# Orden de las tarjetas dentro de una columna: determinista (por posición), posición
# incremental al crear (no todas en 0) y reordenamiento consistente al arrastrar.
RSpec.describe JabvoxTask, type: :model do
  let(:account) { create(:account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Operaciones') }

  let!(:col_a) do
    board.stages.create!(account_id: account.id, name_jabvox: 'A', position_jabvox: 1)
  end
  let!(:col_b) do
    board.stages.create!(account_id: account.id, name_jabvox: 'B', position_jabvox: 2)
  end

  def new_task(stage, title)
    account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id,
                                 title_jabvox: title, status_jabvox: 'open')
  end

  def positions_in(stage)
    account.jabvox_tasks.where(stage_id: stage.id).order(:position_jabvox).pluck(:position_jabvox)
  end

  def titles_in(stage)
    stage.reload
    account.jabvox_tasks.where(stage_id: stage.id).ordered.pluck(:title_jabvox)
  end

  describe 'posición al crear' do
    it 'asigna posiciones incrementales en vez de dejar todas en 0' do
      t1 = new_task(col_a, 'uno')
      t2 = new_task(col_a, 'dos')
      t3 = new_task(col_a, 'tres')

      expect(t1.position_jabvox).to eq(0)
      expect(t2.position_jabvox).to eq(1)
      expect(t3.position_jabvox).to eq(2)
      expect(positions_in(col_a)).to eq([0, 1, 2])
    end

    it 'respeta una posición explícita si se envía' do
      task = account.jabvox_tasks.create!(board_id: board.id, stage_id: col_a.id,
                                          title_jabvox: 'x', position_jabvox: 7)
      expect(task.position_jabvox).to eq(7)
    end

    it 'cada columna cuenta su propia secuencia' do
      new_task(col_a, 'a1')
      b1 = new_task(col_b, 'b1')
      expect(b1.position_jabvox).to eq(0)
    end
  end

  describe '#reorder_within_stage!' do
    it 'reordena dentro de la misma columna y recompacta a 0..n' do
      t1 = new_task(col_a, 'uno')
      t2 = new_task(col_a, 'dos')
      t3 = new_task(col_a, 'tres')

      # Mover "tres" al principio.
      t3.reorder_within_stage!(col_a, 0)

      expect(titles_in(col_a)).to eq(%w[tres uno dos])
      expect(positions_in(col_a)).to eq([0, 1, 2])
      expect(t1.reload.position_jabvox).to eq(1)
      expect(t2.reload.position_jabvox).to eq(2)
    end

    it 'inserta en una posición intermedia' do
      a = new_task(col_a, 'a')
      new_task(col_a, 'b')
      c = new_task(col_a, 'c')

      a.reorder_within_stage!(col_a, 1) # entre b y c
      expect(titles_in(col_a)).to eq(%w[b a c])
      expect(c.reload.position_jabvox).to eq(2)
    end

    it 'mueve entre columnas y recompacta ambas' do
      a1 = new_task(col_a, 'a1')
      new_task(col_a, 'a2')
      new_task(col_b, 'b1')

      a1.reorder_within_stage!(col_b, 0)

      expect(a1.reload.stage_id).to eq(col_b.id)
      expect(titles_in(col_b)).to eq(%w[a1 b1])
      expect(positions_in(col_b)).to eq([0, 1])
      # La columna de origen queda sin huecos.
      expect(titles_in(col_a)).to eq(%w[a2])
      expect(positions_in(col_a)).to eq([0])
    end

    it 'sujeta la posición al rango válido (no deja huecos por índices fuera de rango)' do
      new_task(col_a, 'a')
      b = new_task(col_a, 'b')
      b.reorder_within_stage!(col_a, 99)
      expect(positions_in(col_a)).to eq([0, 1])
      expect(titles_in(col_a)).to eq(%w[a b])
    end
  end

  describe 'orden determinista bajo carga (estrés)' do
    it 'mantiene 0..n-1 sin empates tras crear y reordenar muchas tarjetas' do
      tasks = Array.new(50) { |i| new_task(col_a, "t#{i}") }
      expect(positions_in(col_a)).to eq((0..49).to_a)

      # 200 movimientos aleatorios dentro de la columna.
      srand(1234)
      200.times do
        t = tasks.sample
        t.reorder_within_stage!(col_a, rand(0..49))
      end

      positions = positions_in(col_a)
      expect(positions).to eq((0..49).to_a) # sin huecos ni empates
      expect(positions.uniq.length).to eq(50)
      # El orden es estable entre dos lecturas (no "aleatorio").
      first_read = titles_in(col_a)
      second_read = titles_in(col_a)
      expect(first_read).to eq(second_read)
    end
  end
end
