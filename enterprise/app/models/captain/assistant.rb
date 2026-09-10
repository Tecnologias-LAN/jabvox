# == Schema Information
#
# Table name: captain_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :text
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_captain_assistants_on_account_id  (account_id)
#
class Captain::Assistant < ApplicationRecord
  DESCRIPTION_LENGTH_LIMIT = 500

  include Avatarable
  include Concerns::CaptainToolsHelpers
  include Concerns::Agentable

  self.table_name = 'captain_assistants'

  belongs_to :account
  has_many :documents, class_name: 'Captain::Document', dependent: :destroy_async
  has_many :responses, class_name: 'Captain::AssistantResponse', dependent: :destroy_async
  has_many :faq_suggestions, class_name: 'Captain::FaqSuggestion', dependent: :destroy_async
  has_many :captain_inboxes,
           class_name: 'CaptainInbox',
           foreign_key: :captain_assistant_id,
           dependent: :destroy_async
  has_many :inboxes,
           through: :captain_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :copilot_threads, dependent: :destroy_async
  has_many :scenarios, class_name: 'Captain::Scenario', dependent: :destroy_async
  has_many :agent_sessions, class_name: 'Captain::AgentSession', dependent: :destroy_async

  store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name
  # Tools de agenda/tareas de Jabvox IA, activables por asistente desde Ajustes.
  store_accessor :config, :feature_check_availability, :feature_schedule_appointment,
                 :feature_list_boards, :feature_create_task
  # Escalado a humano: lista de IDs de agentes candidatos a recibir la conversación
  # cuando Jabvox IA hace handoff. Si está vacía, cae a los miembros del inbox.
  store_accessor :config, :handoff_agent_ids
  # Permitir que el asistente escale a un humano (handoff). Activo por defecto; si
  # se pone en false, el asistente NUNCA transfiere y responde siempre él mismo.
  store_accessor :config, :feature_handoff

  # ¿El asistente puede escalar a un humano? Por defecto sí (solo false lo apaga).
  def handoff_enabled?
    value = config['feature_handoff']
    value.nil? || ActiveModel::Type::Boolean.new.cast(value)
  end

  # Agentes candidatos para el escalado (los configurados que sigan en la cuenta).
  def handoff_agents
    ids = Array(handoff_agent_ids).map(&:to_i).uniq.reject(&:zero?)
    return account.users.none if ids.empty?

    account.users.where(id: ids)
  end

  # Cada tool de agenda/tareas está activa salvo que se desactive explícitamente
  # (config sin la clave => true), para no romper asistentes ya existentes.
  JABVOX_AGENDA_TOOLS = {
    'check_availability' => :feature_check_availability,
    'schedule_appointment' => :feature_schedule_appointment,
    'list_board' => :feature_list_boards,
    'create_task' => :feature_create_task
  }.freeze

  validates :name, presence: true
  validates :description, presence: true, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validates :account_id, presence: true

  scope :ordered, -> { order(created_at: :desc) }

  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def available_name
    name
  end

  def available_agent_tools
    tools = self.class.built_in_agent_tools.dup

    custom_tools = account.captain_custom_tools.enabled.map(&:to_tool_metadata)
    tools.concat(custom_tools)

    tools
  end

  def available_tool_ids
    available_agent_tools.pluck(:id)
  end

  def push_event_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  private

  def agent_name
    name.parameterize(separator: '_')
  end

  def agent_tools
    tools = [self.class.resolve_tool_class('faq_lookup').new(self)]
    # La tool de handoff solo si el asistente puede escalar a un humano.
    tools << self.class.resolve_tool_class('handoff').new(self) if handoff_enabled?
    # Aprovisionamiento por chat: solo actúa desde el playground (la tool lo
    # comprueba con state[:source]); segura de tener siempre disponible.
    tools << self.class.resolve_tool_class('update_configuration').new(self)
    # Tools de agenda y tareas de Jabvox IA, activables desde Ajustes.
    tools.concat(jabvox_agenda_tools)
    tools.concat(account.captain_custom_tools.enabled.map { |custom_tool| custom_tool.tool(self) })
    tools
  end

  # Instancia solo las tools de agenda/tareas que estén activas en la config.
  def jabvox_agenda_tools
    JABVOX_AGENDA_TOOLS.filter_map do |tool_id, flag|
      next unless jabvox_agenda_tool_enabled?(flag)

      self.class.resolve_tool_class(tool_id).new(self)
    end
  end

  # Activa por defecto: solo se desactiva si la config trae el flag en false.
  def jabvox_agenda_tool_enabled?(flag)
    value = config[flag.to_s]
    value.nil? || ActiveModel::Type::Boolean.new.cast(value)
  end

  def prompt_context
    {
      name: name,
      description: description,
      product_name: config['product_name'] || 'this product',
      scenarios: scenarios.enabled.map do |scenario|
        {
          title: scenario.title,
          key: scenario.handoff_key,
          description: scenario.description
        }
      end,
      response_guidelines: response_guidelines || [],
      guardrails: guardrails || [],
      # Instrucciones largas personalizadas del asistente (config['instructions']):
      # el Rol/Reglas/Flujo que no cabe en la descripción (máx 500). Se inyectan
      # tal cual en el prompt para que definan el comportamiento de ESTA cuenta.
      custom_instructions: config['instructions'].to_s,
      # Habilita el bloque de instrucciones de agenda en el prompt solo si al menos
      # una tool de agenda está activa, y lista los agentes (nombre -> id) para que
      # el LLM pueda resolver "cita con Fulano" al agente_id correcto.
      agenda_tools_enabled: agenda_tools_active?,
      agenda_agents: agenda_agents_for_prompt,
      handoff_enabled: handoff_enabled?
    }
  end

  def agenda_tools_active?
    JABVOX_AGENDA_TOOLS.values.any? { |flag| jabvox_agenda_tool_enabled?(flag) }
  end

  # Agentes de la cuenta como "id: nombre" para que el asistente sepa a quién
  # corresponde cada nombre al consultar disponibilidad o agendar.
  def agenda_agents_for_prompt
    account.users.order(:name).limit(100).map { |u| { id: u.id, name: u.name } }
  end

  def default_avatar_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/assets/images/dashboard/captain/logo.svg"
  end
end
