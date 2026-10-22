# frozen_string_literal: true

# Catálogo de tipos de nodo disponibles para el motor. Cada nodo declara aquí su
# tipo, su etiqueta, sus puertos y su `items_path`; el motor no conoce ninguno.
class Jabvox::Flows::Registry
  # Disparadores. No tienen handler: el motor siembra su salida con el payload
  # del disparo. La lógica de COINCIDENCIA vive en cada clase (matches?/due?).
  TRIGGERS = [
    Jabvox::Flows::Nodes::Triggers::ManualNode,
    Jabvox::Flows::Nodes::Triggers::WebhookNode,
    Jabvox::Flows::Nodes::Triggers::JabvoxEventNode,
    Jabvox::Flows::Nodes::Triggers::ScheduleNode
  ].freeze

  LOGIC = [
    Jabvox::Flows::Nodes::Logic::IfNode,
    Jabvox::Flows::Nodes::Logic::SwitchNode,
    Jabvox::Flows::Nodes::Logic::LoopNode,
    Jabvox::Flows::Nodes::Logic::MergeNode,
    Jabvox::Flows::Nodes::Logic::DatetimeNode,
    Jabvox::Flows::Nodes::Logic::SetVariableNode,
    Jabvox::Flows::Nodes::Logic::ExpressionNode,
    Jabvox::Flows::Nodes::Logic::DelayNode,
    Jabvox::Flows::Nodes::Logic::WaitUntilNode,
    Jabvox::Flows::Nodes::Logic::WaitResponseNode
  ].freeze

  JABVOX = [
    Jabvox::Flows::Nodes::Jabvox::LabelAddNode,
    Jabvox::Flows::Nodes::Jabvox::LabelRemoveNode,
    Jabvox::Flows::Nodes::Jabvox::LabelFindByAgeNode,
    Jabvox::Flows::Nodes::Jabvox::ConversationAddLabelsNode,
    Jabvox::Flows::Nodes::Jabvox::ContactAddLabelsNode,
    Jabvox::Flows::Nodes::Jabvox::ContactRemoveLabelsNode,
    Jabvox::Flows::Nodes::Jabvox::ConversationSendMessageNode,
    Jabvox::Flows::Nodes::Jabvox::NoteCreateNode,
    Jabvox::Flows::Nodes::Jabvox::WhatsappSendTemplateNode,
    Jabvox::Flows::Nodes::Jabvox::ContactCreateNode,
    Jabvox::Flows::Nodes::Jabvox::ContactUpdateNode,
    Jabvox::Flows::Nodes::Jabvox::ContactFindNode,
    Jabvox::Flows::Nodes::Jabvox::ContactSetCustomAttrsNode,
    Jabvox::Flows::Nodes::Jabvox::LeadSearchNode,
    Jabvox::Flows::Nodes::Jabvox::TaskCreateNode,
    Jabvox::Flows::Nodes::Jabvox::TaskUpdateNode,
    Jabvox::Flows::Nodes::Jabvox::TaskMoveNode,
    Jabvox::Flows::Nodes::Jabvox::TaskDeleteNode,
    Jabvox::Flows::Nodes::Jabvox::KanbanMoveConversationNode,
    Jabvox::Flows::Nodes::Jabvox::KanbanMoveLeadNode,
    Jabvox::Flows::Nodes::Jabvox::LeadListNode,
    Jabvox::Flows::Nodes::Jabvox::LeadGetNode,
    Jabvox::Flows::Nodes::Jabvox::LeadFindByDateNode,
    Jabvox::Flows::Nodes::Jabvox::LeadFindByFieldNode,
    Jabvox::Flows::Nodes::Jabvox::LeadUpdateDetailsNode,
    Jabvox::Flows::Nodes::Jabvox::LeadSetCustomFieldsNode,
    Jabvox::Flows::Nodes::Jabvox::LeadAssignNode,
    Jabvox::Flows::Nodes::Jabvox::LeadUnassignNode,
    Jabvox::Flows::Nodes::Jabvox::ConversationCreateNode,
    Jabvox::Flows::Nodes::Jabvox::ConversationAssignNode,
    Jabvox::Flows::Nodes::Jabvox::ConversationToggleStatusNode,
    Jabvox::Flows::Nodes::Jabvox::TeamAssignNode,
    Jabvox::Flows::Nodes::Jabvox::TypificationCreateNode,
    Jabvox::Flows::Nodes::Jabvox::StateSetManagementStateNode,
    Jabvox::Flows::Nodes::Jabvox::CalendarCreateEventNode,
    Jabvox::Flows::Nodes::Jabvox::CalendarUpdateEventNode,
    Jabvox::Flows::Nodes::Jabvox::CalendarDeleteEventNode,
    Jabvox::Flows::Nodes::Jabvox::EmailSendTemplateNode,
    Jabvox::Flows::Nodes::Jabvox::EmailSendTestNode,
    Jabvox::Flows::Nodes::Jabvox::EmailSendMessageNode,
    Jabvox::Flows::Nodes::Jabvox::SmsSendNode,
    Jabvox::Flows::Nodes::Jabvox::CampaignAddLeadNode,
    Jabvox::Flows::Nodes::Jabvox::OrderCreateNode,
    Jabvox::Flows::Nodes::Jabvox::OrderUpdateNode
  ].freeze

  # Los ÚNICOS nodos que salen a la red. Toda URL pasa antes por UrlGuard; el de
  # base de datos pasa por HostGuard (anti-SSRF) y ejecuta SELECT read-only.
  INTEGRATION = [
    Jabvox::Flows::Nodes::Integration::HttpRequestNode,
    Jabvox::Flows::Nodes::Integration::GraphqlNode,
    Jabvox::Flows::Nodes::Integration::WebhookOutNode,
    Jabvox::Flows::Nodes::Integration::AnalyticsQueryNode
  ].freeze

  ALL = (TRIGGERS + LOGIC + JABVOX + INTEGRATION).freeze

  # El registro queda con los params del CATÁLOGO inyectados: sin ellos la
  # validación de obligatorios no tendría nada que exigir.
  def self.build(with_params: true)
    registry = Jabvox::Flows::Engine::Registry.new
    ALL.each { |node| node.register_on(registry) }
    apply_catalog_params(registry) if with_params
    registry
  end

  # Los nodos declaran su comportamiento; el catálogo, su formulario. Se vuelven
  # a registrar conservando lo ya declarado y añadiendo `params`.
  def self.apply_catalog_params(registry)
    registry.types.each do |type|
      spec = Jabvox::Flows::Catalog.params_spec(type)
      next if spec.empty?

      definition = registry.definition(type)
      registry.register(type, handler: definition.handler, items_path: definition.items_path,
                              outputs: definition.outputs, label: definition.label, params: spec)
    end
  end

  # Clase del nodo por su tipo. Lo usan los disparadores para consultar su
  # matcher sin tener que conocer la lista.
  def self.node_class(type)
    @node_class ||= ALL.index_by { |k| k.respond_to?(:node_type) ? k.node_type : k::TYPE }
    @node_class[type]
  end
end
