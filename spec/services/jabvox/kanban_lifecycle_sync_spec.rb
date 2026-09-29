# frozen_string_literal: true

require 'rails_helper'

# Al cambiar la etapa del contacto, su tarjeta sale de los embudos que solo lo tenían por
# la etapa anterior — pero no de aquellos que lo recogen por otro motivo.
RSpec.describe Jabvox::KanbanLifecycleSync, type: :model do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, lifecycle_stage_jabvox: 'cliente') }

  before { account.update!(jabvox_kanban_enabled_jabvox: true) }

  def funnel_with_card(**attrs)
    funnel = account.jabvox_kanban_funnels.create!(
      { name_jabvox: "Embudo #{SecureRandom.hex(4)}" }.merge(attrs)
    )
    stage = funnel.jabvox_kanban_stages.create!(
      account_id: account.id, name_jabvox: 'Nuevo', position_jabvox: 1
    )
    JabvoxKanbanConversationStage.create!(
      account_id: account.id, jabvox_kanban_funnel_id: funnel.id,
      jabvox_kanban_stage_id: stage.id, contact_id: contact.id
    )
    funnel
  end

  def cards_in(funnel)
    JabvoxKanbanConversationStage.where(jabvox_kanban_funnel_id: funnel.id).count
  end

  it 'retira la tarjeta del embudo que solo lo tenía por la etapa' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: ['cliente'])

    expect { contact.advance_lifecycle!('inactivo') }
      .to change { cards_in(funnel) }.from(1).to(0)
  end

  it 'la conserva si el embudo también recoge la etapa nueva' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: %w[cliente inactivo])

    expect { contact.advance_lifecycle!('inactivo') }.not_to(change { cards_in(funnel) })
  end

  it 'la conserva si el embudo recoge contactos propios' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: ['cliente'],
                              include_own_contacts_jabvox: true)

    expect { contact.advance_lifecycle!('inactivo') }.not_to(change { cards_in(funnel) })
  end

  it 'la conserva si el embudo recoge por la campaña del contacto' do
    campaign = account.jabvox_campaigns.create!(name_jabvox: 'Verano')
    contact.update!(jabvox_campaign_id: campaign.id)
    funnel = funnel_with_card(lifecycle_stages_jabvox: ['cliente'])
    funnel.jabvox_kanban_funnel_campaigns.create!(jabvox_campaign_id: campaign.id)

    expect { contact.advance_lifecycle!('inactivo') }.not_to(change { cards_in(funnel) })
  end

  it 'no toca los embudos que no filtran por etapa' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: [])

    expect { contact.advance_lifecycle!('inactivo') }.not_to(change { cards_in(funnel) })
  end

  it 'no hace nada si el módulo de kanban está apagado' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: ['cliente'])
    account.update!(jabvox_kanban_enabled_jabvox: false)

    expect { contact.advance_lifecycle!('inactivo') }.not_to(change { cards_in(funnel) })
  end

  it 'editar el embudo retira las tarjetas que ya no le corresponden' do
    funnel = funnel_with_card(lifecycle_stages_jabvox: %w[cliente interesado])

    expect { funnel.update!(lifecycle_stages_jabvox: ['interesado']) }
      .to change { cards_in(funnel) }.from(1).to(0)
  end

  it 'editar el embudo conserva a quien sigue encajando' do
    contact.update!(lifecycle_stage_jabvox: 'interesado')
    funnel = funnel_with_card(lifecycle_stages_jabvox: %w[cliente interesado])

    expect { funnel.update!(lifecycle_stages_jabvox: ['interesado']) }
      .not_to(change { cards_in(funnel) })
  end

  it 'no deja tarjetas de otras cuentas al alcance' do
    other = create(:account)
    other.update!(jabvox_kanban_enabled_jabvox: true)
    other_contact = create(:contact, account: other, lifecycle_stage_jabvox: 'cliente')
    other_funnel = other.jabvox_kanban_funnels.create!(
      name_jabvox: 'Ajeno', lifecycle_stages_jabvox: ['cliente']
    )
    other_stage = other_funnel.jabvox_kanban_stages.create!(
      account_id: other.id, name_jabvox: 'Nuevo', position_jabvox: 1
    )
    JabvoxKanbanConversationStage.create!(
      account_id: other.id, jabvox_kanban_funnel_id: other_funnel.id,
      jabvox_kanban_stage_id: other_stage.id, contact_id: other_contact.id
    )

    expect { contact.advance_lifecycle!('inactivo') }
      .not_to(change { cards_in(other_funnel) })
  end
end
