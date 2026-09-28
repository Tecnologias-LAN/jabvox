# frozen_string_literal: true

require 'rails_helper'

# Las claves foráneas salientes de una automatización tienen que ser de su misma cuenta.
#
# El scoping de los controladores protege el recurso que se edita, pero `inbox_id`,
# `sms_provider_id`, `email_template_id` y `target_stage_id` viajan en el formulario: sin
# validarlos se podía crear una automatización propia que enviara por la bandeja de otro
# cliente, gastara su saldo de SMS o renderizara sus plantillas de correo.
RSpec.describe Jabvox::AccountScopedReferences do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:board) { account.jabvox_task_boards.create!(name_jabvox: 'Propio', created_by_id: user.id) }
  let(:stage) do
    board.stages.create!(account_id: account.id, name_jabvox: 'Entrada', position_jabvox: 0)
  end
  let(:own_inbox) { create(:inbox, account: account) }

  let(:other_account) { create(:account) }
  let(:other_inbox) { create(:inbox, account: other_account) }
  let(:other_stage) do
    other_board = other_account.jabvox_task_boards.create!(name_jabvox: 'Ajeno')
    other_board.stages.create!(account_id: other_account.id, name_jabvox: 'Ajena',
                               position_jabvox: 0)
  end

  describe 'automatización de etapa' do
    def build_automation(**attrs)
      stage.automations.build(
        { account_id: account.id, automation_type_jabvox: 'send_message',
          channel_type_jabvox: 'inbox', message_body_jabvox: 'Hola',
          active_jabvox: true }.merge(attrs)
      )
    end

    it 'rechaza una bandeja de otra cuenta' do
      automation = build_automation(inbox_id: other_inbox.id)

      expect(automation).not_to be_valid
      expect(automation.errors[:inbox]).to be_present
    end

    it 'acepta una bandeja propia' do
      expect(build_automation(inbox_id: own_inbox.id)).to be_valid
    end

    it 'rechaza mover tareas a una columna de otra cuenta' do
      automation = build_automation(automation_type_jabvox: 'move_after_hours',
                                    channel_type_jabvox: nil, message_body_jabvox: nil,
                                    trigger_hours_jabvox: 24, target_stage_id: other_stage.id)

      expect(automation).not_to be_valid
      expect(automation.errors[:target_stage]).to be_present
    end
  end

  describe 'automatización de tarea' do
    let(:task) do
      account.jabvox_tasks.create!(board_id: board.id, stage_id: stage.id,
                                   title_jabvox: 'Pendiente', created_by_id: user.id)
    end

    def build_automation(**attrs)
      task.automations.build(
        { account_id: account.id, name_jabvox: 'Aviso', channel_jabvox: 'inbox',
          recipients_jabvox: 'lead', interval_unit_jabvox: 'day', interval_count_jabvox: 1,
          body_jabvox: 'Hola', created_by_id: user.id }.merge(attrs)
      )
    end

    it 'rechaza una bandeja de otra cuenta' do
      automation = build_automation(inbox_id: other_inbox.id)

      expect(automation).not_to be_valid
      expect(automation.errors[:inbox]).to be_present
    end

    it 'acepta una bandeja propia' do
      expect(build_automation(inbox_id: own_inbox.id)).to be_valid
    end
  end

  # Los campos son opcionales: sin canal configurado la automatización sigue siendo válida.
  it 'no exige las referencias, solo que sean de la cuenta cuando existen' do
    automation = stage.automations.build(account_id: account.id,
                                         automation_type_jabvox: 'send_message',
                                         channel_type_jabvox: 'email',
                                         message_body_jabvox: 'Hola', active_jabvox: true)

    expect(automation).to be_valid
  end
end
