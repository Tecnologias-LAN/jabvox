# frozen_string_literal: true

# Cron jobs de Hermes de la cuenta, vistos y gestionados desde el Chat IA. TODO se hace
# con el SCOPED TOKEN del handoff de ESTA cuenta: Hermes solo expone/acepta los cron del
# profile de la cuenta, así que el aislamiento lo garantiza el token (403 con token ajeno).
#
#   GET    .../jabvox/ai_chat_hermes_cron_jobs           → lista (read: cualquier miembro)
#   POST   .../jabvox/ai_chat_hermes_cron_jobs           → crea (write: requiere permiso)
#   PATCH  .../jabvox/ai_chat_hermes_cron_jobs/:id/toggle → pausa/reanuda (write)
#   DELETE .../jabvox/ai_chat_hermes_cron_jobs/:id        → elimina (write)
class Api::V1::Accounts::Jabvox::AiChatHermesCronJobsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action :require_operational_handoff
  # Leer (index) lo puede cualquier miembro; crear/pausar/borrar exige el permiso de gestión.
  before_action -> { jabvox_authorize_write!('jabvox_ai_chat_manage') }

  def index
    result = service.list_cron_jobs(token, base_url: base_url)
    respond(result, key: :jobs, default: [])
  end

  def create
    attrs = params.permit(:name, :schedule, :prompt, :blueprint, :enabled).to_h
    return render(json: { error: 'name y schedule requeridos' }, status: :unprocessable_entity) if attrs['name'].blank? || attrs['schedule'].blank?

    result = service.create_cron_job(token, attrs, base_url: base_url)
    respond(result, key: :job)
  end

  def toggle
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    result = service.set_cron_job_enabled(token, params[:id], enabled, base_url: base_url)
    respond(result, key: :job)
  end

  def destroy
    result = service.delete_cron_job(token, params[:id], base_url: base_url)
    if result.success?
      head :no_content
    else
      render json: { error: result.error }, status: :bad_gateway
    end
  end

  private

  def service
    @service ||= Jabvox::Hermes::Client.new
  end

  def handoff
    @handoff ||= Current.account.jabvox_context_forge_handoff
  end

  def token
    handoff.scoped_token
  end

  def base_url
    handoff.hermes_url
  end

  def require_operational_handoff
    return if handoff&.ready_for_chat?

    render json: { error: 'La cuenta no tiene un Hermes conectado.' },
           status: :unprocessable_entity
  end

  def respond(result, key:, default: nil)
    if result.success?
      render json: { key => (result.data || default) }
    else
      render json: { error: result.error }, status: :bad_gateway
    end
  end
end
