# frozen_string_literal: true

# Capa de servicio interna: traduce una tool YA AUTORIZADA a una acción real sobre los
# modelos/servicios de dominio de Jabvox. Es la frontera que garantiza que Hermes NUNCA
# ejecuta SQL ni toca la BD directamente: todo pasa por ActiveRecord con el account SIEMPRE
# forzado a la cuenta del contexto (nunca uno enviado por el LLM), evitando cross-account.
#
# Cada acción se despacha por (method, path) a un handler explícito (whitelist). Un path no
# mapeado se rechaza — no hay ejecución genérica de HTTP ni de SQL.
class Jabvox::Hermes::ServiceLayer
  UnknownAction = Class.new(StandardError)

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Enruta a un handler concreto. `path` ya viene con placeholders resueltos.
  def call(method:, path:, params:)
    key = "#{method.to_s.upcase} #{normalize(path)}"
    handler = ROUTES[key]
    raise UnknownAction, "acción no soportada: #{key}" unless handler

    send(handler, params)
  end

  private

  # Normaliza un path concreto a su plantilla (labels/5 → labels/:id) para el ruteo.
  def normalize(path)
    path.gsub(%r{/\d+}, '/:id')
  end

  # Whitelist de rutas → handler. Coincide con ToolRegistry.
  ROUTES = {
    'GET labels' => :list_labels,
    'POST labels' => :create_label,
    'PATCH labels/:id' => :update_label,
    'DELETE labels/:id' => :delete_label,
    'GET conversations/meta' => :conversations_meta,
    'POST conversations/:id/messages' => :reply_conversation
  }.freeze

  # --- Handlers de dominio (account SIEMPRE = @account, nunca del LLM) ---

  def list_labels(_params)
    @account.labels.map { |l| { id: l.id, title: l.title, color: l.color } }
  end

  def create_label(params)
    label = @account.labels.create!(title: params[:title])
    { id: label.id, title: label.title }
  end

  def update_label(params)
    label = @account.labels.find(params[:id]) # scoped a la cuenta → no cross-account
    label.update!(title: params[:title])
    { id: label.id, title: label.title }
  end

  def delete_label(params)
    label = @account.labels.find(params[:id])
    label.destroy!
    { id: params[:id], deleted: true }
  end

  def conversations_meta(_params)
    { open: @account.conversations.open.count, total: @account.conversations.count }
  end

  def reply_conversation(params)
    conv = @account.conversations.find(params[:id]) # scoped a la cuenta
    msg = conv.messages.create!(
      account_id: @account.id, message_type: :outgoing, content: params[:content],
      sender: @user, inbox_id: conv.inbox_id
    )
    { id: msg.id, conversation_id: conv.display_id }
  end
end
