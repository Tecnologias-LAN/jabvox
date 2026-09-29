# frozen_string_literal: true

require 'rails_helper'

# Borrar un embudo arrastra sus etapas, y con ellas sus tarjetas. `jabvox_kanban_stage_id`
# es NOT NULL, así que con `dependent: :nullify` esto reventaba con violación de FK y la
# API devolvía un 500.
RSpec.describe JabvoxKanbanFunnel, type: :model do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:funnel) { account.jabvox_kanban_funnels.create!(name_jabvox: 'Ventas') }

  def stage(name, position)
    funnel.jabvox_kanban_stages.create!(
      account_id: account.id, name_jabvox: name, position_jabvox: position
    )
  end

  it 'se borra con sus tarjetas dentro' do
    first = stage('Nuevo', 1)
    JabvoxKanbanConversationStage.create!(
      account_id: account.id, jabvox_kanban_funnel_id: funnel.id,
      jabvox_kanban_stage_id: first.id, contact_id: contact.id
    )

    expect { funnel.destroy! }.to change(JabvoxKanbanConversationStage, :count).by(-1)
    expect(described_class.exists?(funnel.id)).to be(false)
  end

  it 'se borra aunque una automatización apunte a otra etapa del mismo embudo' do
    origin = stage('Nuevo', 1)
    target = stage('Cerrado', 2)
    JabvoxKanbanStageAutomation.create!(
      account_id: account.id, jabvox_kanban_stage_id: origin.id, name: 'mover',
      automation_type: 'move_after_hours', trigger_value_jabvox: 2,
      trigger_unit_jabvox: 'hours', target_stage_id: target.id, active: true
    )

    expect { funnel.destroy! }.not_to raise_error
  end

  it 'se borra aunque una etapa auto-avance hacia otra' do
    origin = stage('Nuevo', 1)
    target = stage('Cerrado', 2)
    origin.update!(auto_advance_target_stage_id: target.id)

    expect { funnel.destroy! }.not_to raise_error
  end
end
