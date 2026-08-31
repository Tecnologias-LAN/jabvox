# frozen_string_literal: true

# Historial de ejecuciones de la cuenta: listado con filtros, resumen y el
# detalle con la traza por paso.
class Api::V1::Accounts::Jabvox::Flows::RunsController < Api::V1::Accounts::Jabvox::Flows::BaseController
  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50

  def index
    scope = filtered_scope
    total = scope.count
    limit = page_limit
    offset = params[:offset].to_i.clamp(0, Float::INFINITY).to_i
    page = scope.includes(:flow).order(created_at: :desc).limit(limit).offset(offset)

    render json: { 'items' => page.map { |run| list_item(run) }, 'total' => total,
                   'limit' => limit, 'offset' => offset,
                   'hasMore' => (offset + page.size) < total }
  end

  # Resumen para las tarjetas. Las PRUEBAS de un paso quedan fuera de todas las
  # métricas y se reportan aparte.
  def stats
    days = params[:days].present? ? params[:days].to_i.clamp(1, 365) : 30
    window = runs_scope.where(created_at: days.days.ago..)
    production = window.reject { |run| Jabvox::Flows::Serializer.test?(run.trigger) }
    render json: presenter.stats(days, production, window)
  end

  def show
    run = runs_scope.includes(:flow, :version).find(params[:id])
    render json: presenter.detail(run)
  end

  # Reanuda una ejecución en espera. Es IDEMPOTENTE: si otro despertar ya la
  # continuó, se responde `resumed: false` sin volver a ejecutar nada.
  def resume
    run = runs_scope.find(params[:id])
    return render_error('La ejecución no está en espera.', status: :conflict) unless run.waiting?

    outcome = Jabvox::Flows::RunService.new(run).resume(payload: resume_payload)
    render json: { 'runId' => run.id.to_s, 'status' => run.reload.status,
                   'resumed' => outcome != :not_waiting }
  end

  private

  def presenter
    Jabvox::Flows::RunPresenter
  end

  def page_limit
    return DEFAULT_LIMIT if params[:limit].blank?

    params[:limit].to_i.clamp(1, MAX_LIMIT)
  end

  def filtered_scope
    scope = runs_scope
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(flow_id: params[:flowId]) if params[:flowId].present?
    apply_test_filter(apply_date_filter(scope))
  end

  def apply_date_filter(scope)
    scope = scope.where(created_at: params[:from]..) if params[:from].present?
    scope = scope.where(created_at: ..params[:to]) if params[:to].present?
    scope
  end

  # Las pruebas se incluyen por defecto; se distinguen por la marca del trigger.
  def apply_test_filter(scope)
    return scope.where("trigger->>'isTest' = 'true'") if params[:onlyTests].to_s == 'true'
    return scope unless params[:includeTests].to_s == 'false'

    scope.where("trigger->>'isTest' IS DISTINCT FROM 'true'")
  end

  def list_item(run)
    counts = step_counts[run.id] || { total: 0, failed: 0 }
    Jabvox::Flows::Serializer.run_list_item(
      run, flow_name: run.flow&.name, steps_total: counts[:total], steps_failed: counts[:failed]
    )
  end

  # Conteo de pasos de TODA la página en una sola consulta.
  def step_counts
    @step_counts ||= begin
      ids = filtered_scope.order(created_at: :desc).limit(page_limit)
                          .offset(params[:offset].to_i).pluck(:id)
      rows = JabvoxFlowRunStep.where(flow_run_id: ids).group(:flow_run_id, :status).count
      rows.each_with_object({}) do |((run_id, status), count), acc|
        entry = acc[run_id] ||= { total: 0, failed: 0 }
        entry[:total] += count
        entry[:failed] += count if status == 'failed'
      end
    end
  end

  def resume_payload
    raw = params[:payload]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
  end
end
