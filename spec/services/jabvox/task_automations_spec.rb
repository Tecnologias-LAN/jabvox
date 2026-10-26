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

  # WhatsApp a una "Dirección manual" (número suelto, el del responsable): antes fallaba
  # siempre con `sin_contacto` porque deliver_template exigía un contacto existente. Ahora
  # busca/crea el contacto por ese número en la cuenta.
  describe 'plantilla WhatsApp a número manual' do
    let(:wa_channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    end

    def wa_automation(target)
      target.automations.create!(
        account_id: account.id, name_jabvox: 'Recordatorio', channel_jabvox: 'whatsapp_template',
        recipients_jabvox: 'manual', manual_phone_jabvox: '3024696389',
        inbox_id: wa_channel.inbox.id, template_name_jabvox: 'recordatorio_tareas',
        template_language_jabvox: 'es', interval_unit_jabvox: 'day', interval_count_jabvox: 1,
        start_at_jabvox: 2.days.ago, created_by_id: user.id
      )
    end

    before { allow(SendReplyJob).to receive(:perform_now) }

    it 'crea el contacto por el número manual y NO falla con sin_contacto' do
      pendiente = task
      automation = wa_automation(pendiente)

      expect { Jabvox::TaskAutomationDispatchService.new(automation).perform }
        .to change { account.contacts.where(phone_number: '+3024696389').count }.by(1)

      run = pendiente.automation_runs.last
      expect(run.detail_jabvox.to_s).not_to include('sin_contacto')
      expect(run.status_jabvox).to eq('sent')
    end

    it 'reutiliza un contacto existente con ese número' do
      create(:contact, account: account, phone_number: '+3024696389', name: 'Keiner')
      pendiente = task
      automation = wa_automation(pendiente)

      expect { Jabvox::TaskAutomationDispatchService.new(automation).perform }
        .not_to(change { account.contacts.count })
      expect(pendiente.automation_runs.last.detail_jabvox.to_s).not_to include('sin_contacto')
    end
  end

  # WhatsApp a RESPONSABLES (assignees): un responsable es un usuario sin teléfono ni
  # contacto, así que antes la plantilla fallaba con `sin_contacto`. Ahora se mapea un
  # contacto a cada responsable y la plantilla sale por ese contacto.
  describe 'plantilla WhatsApp a responsables (mapeo responsable->contacto)' do
    let(:wa_channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:responsable) { create(:user, account: account, name: 'Melany') }
    let(:contacto_responsable) do
      create(:contact, account: account, name: 'Contacto Melany', phone_number: '+573001112233')
    end

    before { allow(SendReplyJob).to receive(:perform_now) }

    def wa_assignee_automation(target, map:)
      target.automations.create!(
        account_id: account.id, name_jabvox: 'Aviso responsable', channel_jabvox: 'whatsapp_template',
        recipients_jabvox: 'assignees', inbox_id: wa_channel.inbox.id,
        template_name_jabvox: 'recordatorio_tareas', template_language_jabvox: 'es',
        interval_unit_jabvox: 'day', interval_count_jabvox: 1, start_at_jabvox: 2.days.ago,
        created_by_id: user.id, assignee_contact_map_jabvox: map
      )
    end

    it 'envía la plantilla al contacto mapeado del responsable (NO falla con sin_contacto)' do
      pendiente = task
      pendiente.sync_assignees!([responsable.id])
      automation = wa_assignee_automation(pendiente, map: { responsable.id.to_s => contacto_responsable.id })

      Jabvox::TaskAutomationDispatchService.new(automation).perform

      run = pendiente.automation_runs.last
      expect(run.detail_jabvox.to_s).not_to include('sin_contacto')
      expect(run.status_jabvox).to eq('sent')
      # La conversación se creó sobre el contacto mapeado, no sobre otro.
      expect(contacto_responsable.conversations.count).to be >= 1
    end

    it 'falla solo ese responsable si no tiene contacto mapeado (sin romper el resto)' do
      pendiente = task
      pendiente.sync_assignees!([responsable.id])
      automation = wa_assignee_automation(pendiente, map: {}) # sin mapeo

      Jabvox::TaskAutomationDispatchService.new(automation).perform

      run = pendiente.automation_runs.last
      expect(run.detail_jabvox.to_s).to include('sin_contacto')
      expect(run.detail_jabvox.to_s).to include('Melany') # el error nombra al responsable
    end

    it 'rechaza un mapeo que apunta a un contacto de OTRA cuenta' do
      otra_cuenta = create(:account)
      contacto_ajeno = create(:contact, account: otra_cuenta, phone_number: '+573009998877')
      pendiente = task

      automation = pendiente.automations.build(
        account_id: account.id, name_jabvox: 'x', channel_jabvox: 'whatsapp_template',
        recipients_jabvox: 'assignees', inbox_id: wa_channel.inbox.id,
        template_name_jabvox: 't', template_language_jabvox: 'es',
        interval_unit_jabvox: 'day', interval_count_jabvox: 1, start_at_jabvox: 2.days.ago,
        created_by_id: user.id, assignee_contact_map_jabvox: { responsable.id.to_s => contacto_ajeno.id }
      )

      expect(automation.valid?).to be(false)
      expect(automation.errors[:assignee_contact_map_jabvox].join).to include('no son de esta cuenta')
    end
  end
end
