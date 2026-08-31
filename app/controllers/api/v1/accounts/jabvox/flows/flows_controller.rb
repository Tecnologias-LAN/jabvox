# frozen_string_literal: true

# CRUD de flujos, versionado del grafo y disparo de ejecuciones.
class Api::V1::Accounts::Jabvox::Flows::FlowsController < Api::V1::Accounts::Jabvox::Flows::BaseController
  before_action :set_flow, except: [:index, :create, :quota]

  # La cuota se comprueba dentro de la transacción del servicio; aquí solo se
  # traduce el fallo a 422 con el mensaje que ve el usuario.
  rescue_from Jabvox::Flows::QuotaService::QuotaExceeded do |error|
    render json: { error: error.message, quota: quota_service.as_json }, status: :unprocessable_entity
  end

  def index
    flows = flows_scope.includes(:current_version).order(updated_at: :desc)
    flows = flows.where(status: params[:status]) if params[:status].present?
    flows = flows.where(folder_id: params[:folderId]) if params[:folderId].present?
    render json: flows.map { |flow| serialize_flow(flow) }
  end

  def show
    render json: serialize_flow(@flow, with_graph: true)
  end

  def create
    flow = nil
    quota_service.create! do
      flow = flows_scope.new(flow_params.slice(:name, :description, :folder_id))
      raise ActiveRecord::Rollback unless flow.save
    end
    return render_error(flow.errors.full_messages.to_sentence) unless flow&.persisted?

    render json: serialize_flow(flow, with_graph: true), status: :created
  end

  # Tope de flujos de la cuenta, para que la interfaz avise antes de intentar crear.
  def quota
    render json: quota_service.as_json
  end

  # El cambio de estado va por aquí: activar EXIGE que el grafo pase la
  # validación estricta, para no dejar activo un flujo que fallaría al dispararse.
  def update
    return if activating? && !activation_allowed?

    return render_error(@flow.errors.full_messages.to_sentence) unless @flow.update(flow_params)

    render json: serialize_flow(@flow, with_graph: true)
  end

  # Borrado permanente. Un flujo ACTIVO no se borra por accidente: primero se
  # desactiva.
  def destroy
    return render_error('Desactiva el flujo antes de borrarlo.', status: :conflict) if @flow.active?

    @flow.destroy!
    head :no_content
  end

  # Duplicar también consume cuota: crea un flujo nuevo.
  def duplicate
    copy = nil
    quota_service.create! do
      copy = flows_scope.create!(name: "#{@flow.name} (copia)", description: @flow.description,
                                 folder_id: @flow.folder_id)
      graph = @flow.current_version&.graph || { 'nodes' => [], 'edges' => [] }
      version = copy.versions.create!(version: 1, graph: graph, created_by: current_user.id)
      copy.update!(current_version: version)
    end
    render json: serialize_flow(copy.reload, with_graph: true), status: :created
  end

  # Guarda el grafo como una versión NUEVA. Valida en modo PERMISIVO porque el
  # editor autoguarda a media construcción: solo se rechaza lo que haría el
  # grafo imposible de cargar.
  def save_version
    graph = graph_from_params
    mode = params[:strict] ? :strict : :permissive
    result = validate_graph(graph, mode: mode)
    if result.blocking?
      return render json: { error: 'El flujo tiene problemas que impiden guardarlo.',
                            validation: Jabvox::Flows::Serializer.validation(result) },
                    status: :unprocessable_entity
    end

    render json: serialize_flow(create_version!(graph), with_graph: true)
  end

  # Diagnóstico ESTRICTO que nunca falla: responde 200 con la lista de problemas.
  # Con `nodes`/`edges` valida el lienzo actual; sin ellos, la versión guardada.
  def validate
    graph = params[:nodes].present? ? graph_from_params : (@flow.current_version&.graph || {})
    render json: Jabvox::Flows::Serializer.validation(validate_graph(graph, mode: :strict))
  end

  def versions
    current_id = @flow.current_version_id
    list = @flow.versions.includes(:creator).order(version: :desc)
    render json: list.map { |v| Jabvox::Flows::Serializer.version_summary(v, current_id) }
  end

  def version
    found = @flow.versions.find_by!(version: params[:v])
    render json: Jabvox::Flows::Serializer.version(found)
  end

  # Restaurar AVANZA el historial: copia el grafo antiguo en una versión nueva.
  # Así nunca se pierde lo que había.
  def restore_version
    source = @flow.versions.find_by!(version: params[:v])
    created = create_version!(source.graph)
    render json: Jabvox::Flows::Serializer.version(created.current_version)
  end

  # Ejecuta el flujo a mano. Se encola: la respuesta es 202 con el id del run.
  def run
    version = @flow.current_version
    return render_error('El flujo no tiene ningún grafo guardado todavía.') if version.nil?

    created = build_run(version, trigger_payload.merge('type' => 'trigger.manual'))
    Jabvox::Flows::RunJob.perform_later(created.id)
    render json: Jabvox::Flows::Serializer.run(created), status: :accepted
  end

  # EJECUTAR DESDE AQUÍ: ejecución normal que arranca en un nodo concreto y
  # recorre todo lo alcanzable desde él.
  def run_from
    version = @flow.current_version
    return render_error('El flujo no tiene ningún grafo guardado todavía.') if version.nil?
    return render_not_found unless node_in_graph?(version, params[:nodeId])

    trigger = trigger_payload.merge('type' => 'trigger.__from', 'fromNodeId' => params[:nodeId])
    created = build_run(version, trigger)
    Jabvox::Flows::RunFromJob.perform_later(created.id, params[:nodeId])
    render json: { 'runId' => created.id.to_s, 'status' => created.status, 'queued' => true },
           status: :accepted
  end

  # PROBAR UN PASO: ejecuta un solo nodo y responde SÍNCRONAMENTE con su salida.
  def run_node
    version = @flow.current_version
    return render_error('El flujo no tiene ningún grafo guardado todavía.') if version.nil?
    return render_not_found unless node_in_graph?(version, params[:nodeId])

    render json: Jabvox::Flows::TestNodeService.new(
      flow: @flow, version: version, node_id: params[:nodeId], user: current_user,
      context: { payload: trigger_payload,
                 prior_outputs: params[:priorOutputs]&.to_unsafe_h || {},
                 use_last_run_context: params[:useLastRunContext].to_s != 'false' }
    ).call
  end

  def runs
    limit = params[:limit].to_i.clamp(1, 100)
    limit = 10 if params[:limit].blank?
    list = @flow.runs.order(created_at: :desc).limit(limit)
    render json: list.map { |r| Jabvox::Flows::Serializer.run(r) }
  end

  private

  def quota_service
    @quota_service ||= Jabvox::Flows::QuotaService.new(Current.account)
  end

  def set_flow
    @flow = flows_scope.find(params[:id])
  end

  def flow_params
    params.permit(:name, :description, :status, :folderId)
          .to_h.transform_keys { |k| k == 'folderId' ? 'folder_id' : k }
          .with_indifferent_access.slice(:name, :description, :status, :folder_id)
  end

  def activating?
    flow_params[:status].to_s == 'active' && !@flow.active?
  end

  # Un flujo solo se ACTIVA si su grafo pasa la validación estricta.
  def activation_allowed?
    graph = @flow.current_version&.graph
    if graph.blank?
      render_error('No puedes activar un flujo sin grafo guardado.')
      return false
    end

    result = validate_graph(graph, mode: :strict)
    return true if result.valid?

    render json: { error: 'El flujo no se puede activar: corrige los problemas indicados.',
                   validation: Jabvox::Flows::Serializer.validation(result) },
           status: :unprocessable_entity
    false
  end

  def validate_graph(graph, mode:)
    Jabvox::Flows::Validation::GraphValidator.call(graph, mode: mode, registry: registry)
  end

  # Cada guardado crea una versión nueva: el historial nunca se reescribe.
  def create_version!(graph)
    @flow.with_lock do
      next_number = (@flow.versions.maximum(:version) || 0) + 1
      version = @flow.versions.create!(version: next_number, graph: graph,
                                       created_by: current_user.id)
      @flow.update!(current_version: version)
    end
    @flow.reload
  end

  def build_run(version, trigger)
    JabvoxFlowRun.create!(account_id: Current.account.id, flow: @flow, version: version,
                          status: :pending, trigger: trigger, triggered_by: current_user.id)
  end

  def trigger_payload
    raw = params[:payload]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
  end

  def node_in_graph?(version, node_id)
    Array(version.graph['nodes']).any? { |node| node['id'].to_s == node_id.to_s }
  end
end
