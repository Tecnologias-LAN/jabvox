# frozen_string_literal: true

# Base de la API de FLUJOS. Hereda el gateo por módulo del base Jabvox: con
# `jabvox_advanced_automations` apagado, TODA la API responde 403 sin llegar a
# tocar la base de datos.
class Api::V1::Accounts::Jabvox::Flows::BaseController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_advanced_automations'

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  # Multi-tenant: TODA lectura parte de la cuenta actual. Un flujo de otra cuenta
  # no es "prohibido", es inexistente.
  def flows_scope
    Current.account.jabvox_flows
  end

  def runs_scope
    JabvoxFlowRun.where(account_id: Current.account.id)
  end

  def registry
    @registry ||= Jabvox::Flows::Registry.build
  end

  def render_not_found(_error = nil)
    render json: { error: 'No se encontró el recurso solicitado.' }, status: :not_found
  end

  def render_error(message, status: :unprocessable_entity)
    render json: { error: message }, status: status
  end

  # El grafo llega en el cuerpo como `nodes`/`edges`. `notes` son las notas
  # adhesivas: solo visuales, el motor y la validación no las miran.
  def graph_from_params
    { 'nodes' => params[:nodes] || [], 'edges' => params[:edges] || [],
      'notes' => params[:notes] || [] }.as_json
  end

  def serialize_flow(flow, with_graph: false)
    Jabvox::Flows::Serializer.flow(flow, with_graph: with_graph)
  end
end
