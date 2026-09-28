# frozen_string_literal: true

require 'rails_helper'

# Automatizaciones de tareas de punta a punta.
#
# Al retirar Leads quedaron tres referencias a `task.jabvox_lead`, una de ellas en el
# `includes` del despachador por lotes: el job horario reventaba con
# AssociationNotFoundError y NINGUNA automatización recurrente se ejecutaba.
RSpec.describe 'Jabvox task automations' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Cliente', email: 'c@test.local') }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Tablero', created_by_id: user.id) }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Entrada', position_jabvox: 0)
  end
  let(:target_stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Atascadas', position_jabvox: 1)
  end

  before { account.update!(jabvox_tasks_enabled_jabvox: true) }

  def task(**attrs)
    account.jabvox_tasks.create!(
      { board_id: board.id, stage_id: stage.id, title_jabvox: 'Pendiente',
        contact_id: contact.id, created_by_id: user.id }.merge(attrs)
    )
  end

  def recurring_automation(target, **attrs)
    target.automations.create!(
      { account_id: account.id, name_jabvox: 'Aviso', channel_jabvox: 'email',
        recipients_jabvox: 'lead', interval_unit_jabvox: 'day', interval_count_jabvox: 1,
        body_jabvox: 'Hola {{lead_name}}', subject_jabvox: 'Asunto',
        start_at_jabvox: 2.days.ago, created_by_id: user.id }.merge(attrs)
    )
  end

  describe 'automatización de etapa por tiempo' do
    it 'mueve la tarea que lleva demasiado sin tocarse' do
      stage.automations.create!(account_id: account.id, automation_type_jabvox: 'move_after_hours',
                                trigger_hours_jabvox: 24, target_stage_id: target_stage.id,
                                active_jabvox: true)
      atascada = task
      atascada.update_column(:updated_at, 30.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      Jabvox::TaskTimeAutomationsService.new.perform

      expect(atascada.reload.stage_id).to eq(target_stage.id)
    end

    it 'no mueve la que se tocó hace poco' do
      stage.automations.create!(account_id: account.id, automation_type_jabvox: 'move_after_hours',
                                trigger_hours_jabvox: 24, target_stage_id: target_stage.id,
                                active_jabvox: true)
      reciente = task

      Jabvox::TaskTimeAutomationsService.new.perform

      expect(reciente.reload.stage_id).to eq(stage.id)
    end

    it 'no dispara una automatización desactivada' do
      stage.automations.create!(account_id: account.id, automation_type_jabvox: 'move_after_hours',
                                trigger_hours_jabvox: 24, target_stage_id: target_stage.id,
                                active_jabvox: false)
      atascada = task
      atascada.update_column(:updated_at, 30.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      Jabvox::TaskTimeAutomationsService.new.perform

      expect(atascada.reload.stage_id).to eq(stage.id)
    end
  end

  describe 'despacho de automatizaciones recurrentes' do
    it 'no revienta al recorrer el lote' do
      recurring_automation(task)

      expect { Jabvox::TaskAutomationsDispatchService.new.perform }.not_to raise_error
    end

    it 'deja registro de la ejecución y programa la siguiente' do
      pendiente = task
      automation = recurring_automation(pendiente)
      anterior = automation.next_run_at_jabvox

      Jabvox::TaskAutomationsDispatchService.new.perform

      automation.reload
      expect(automation.runs_count_jabvox).to eq(1)
      expect(automation.next_run_at_jabvox).to be > anterior
      expect(pendiente.automation_runs.count).to eq(1)
    end

    it 'resuelve el contacto de la tarea como destinatario' do
      pendiente = task
      recurring_automation(pendiente)

      Jabvox::TaskAutomationsDispatchService.new.perform

      # Sin SMTP en la cuenta el envío falla, pero el destinatario se resolvió: el detalle
      # lleva su nombre. Antes ni se llegaba aquí.
      expect(pendiente.automation_runs.last.detail_jabvox).to include('Cliente')
    end

    # Una tarea cerrada no debe seguir mandando recordatorios.
    it 'se salta las automatizaciones de una tarea completada' do
      completada = task(status_jabvox: 'done')
      automation = recurring_automation(completada)

      Jabvox::TaskAutomationsDispatchService.new.perform

      expect(automation.reload.runs_count_jabvox).to eq(0)
    end
  end
end
