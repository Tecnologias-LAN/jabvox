# frozen_string_literal: true

require 'rails_helper'

# GATING DE NODOS POR MÓDULO ACTIVO. El editor solo debe ofrecer nodos cuyos
# módulos estén activos en la cuenta: un nodo de una función apagada que se puede
# arrastrar pero nunca ejecutará es confuso y rompe el principio de "si no tienes
# el módulo, no existe". El núcleo (triggers/logic/integration/contactos/
# conversaciones) está SIEMPRE disponible.
RSpec.describe Jabvox::Flows::Catalog do
  let(:account) { create(:account) }

  # Desactiva por defecto todo módulo gateado para partir de un estado conocido:
  # un create(:account) puede traer features activas de fábrica.
  before do
    described_class.reset!
    described_class::MODULE_FEATURE.each_value do |feature|
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with(feature).and_return(false)
    end
  end

  def types_for(acc)
    described_class.all_for(acc).map { |n| n['type'] }
  end

  it 'sin módulos gateados: núcleo visible, nodos de módulo ocultos' do
    visible = types_for(account)

    # Núcleo y motor siempre presentes.
    %w[trigger.manual logic.if logic.loop integration.http_request
       jabvox.contact.find jabvox.conversation.send_message].each do |t|
      expect(visible).to include(t), "#{t} debería estar SIEMPRE visible"
    end

    # Nodos de módulos apagados, ausentes.
    %w[jabvox.task.search jabvox.task.create jabvox.kanban.list
       jabvox.sms.send jabvox.email.send_template jabvox.calendar.create_event
       jabvox.whatsapp.send_template jabvox.order.create].each do |t|
      expect(visible).not_to include(t), "#{t} NO debería verse con su módulo apagado"
    end
  end

  it 'activar un módulo revela exactamente sus nodos' do
    allow(account).to receive(:feature_enabled?).with('jabvox_tasks').and_return(true)

    visible = types_for(account)
    expect(visible).to include('jabvox.task.search', 'jabvox.task.create', 'jabvox.task.move')
    # Kanban sigue apagado.
    expect(visible).not_to include('jabvox.kanban.list')
  end

  it 'modules_for reporta activos y ocultos de forma coherente' do
    allow(account).to receive(:feature_enabled?).with('jabvox_kanban').and_return(true)

    mods = described_class.modules_for(account)
    expect(mods[:enabled]).to include('kanban')
    expect(mods[:hidden]).to include('tareas', 'sms', 'email')
    expect(mods[:enabled] & mods[:hidden]).to be_empty
  end

  it 'cada módulo del catálogo o es núcleo o está mapeado a una feature' do
    # Evita que un nodo nuevo con un `module` no mapeado se cuele siempre visible
    # sin querer (o, peor, se gatee por un typo). Los módulos núcleo son explícitos.
    core_modules = %w[contactos conversaciones etiquetas campañas].freeze
    catalog_modules = described_class.all.filter_map { |n| n['module'] }.uniq
    catalog_modules.each do |mod|
      mapped = described_class::MODULE_FEATURE.key?(mod) || core_modules.include?(mod)
      expect(mapped).to be(true), "módulo '#{mod}' no está ni mapeado ni declarado núcleo"
    end
  end
end
