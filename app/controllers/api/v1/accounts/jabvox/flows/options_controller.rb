# frozen_string_literal: true

# Opciones dinámicas de los params (`optionsSource`): bandejas, agentes,
# plantillas, tableros… siempre de la cuenta actual.
class Api::V1::Accounts::Jabvox::Flows::OptionsController < Api::V1::Accounts::Jabvox::Flows::BaseController
  def show
    render json: service.call(params[:kind], dependencies)
  rescue Jabvox::Flows::OptionsService::UnknownKind,
         Jabvox::Flows::OptionsService::MissingDependency => e
    render_error(e.message, status: :bad_request)
  end

  private

  def service
    Jabvox::Flows::OptionsService.new(Current.account)
  end

  # Dependencias declaradas por `dependsOn` en el catálogo.
  def dependencies
    params.permit(:funnelId, :boardId, :inboxId).to_h.symbolize_keys
  end
end
